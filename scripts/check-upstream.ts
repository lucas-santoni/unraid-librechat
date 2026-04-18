import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Octokit } from "@octokit/rest";

type Pin = { ref: string; sha: string };
type Target = {
  name: string;
  owner: string;
  repo: string;
  file: string;
};

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..");

const targets: Target[] = [
  { name: "LibreChat", owner: "danny-avila", repo: "LibreChat",
    file: join(repoRoot, "versions/librechat.json") },
];

const token = process.env.GITHUB_TOKEN;
if (!token) {
  console.error("GITHUB_TOKEN is required");
  process.exit(1);
}
const octokit = new Octokit({ auth: token });
const repoSlugEnv = process.env.REPO;
if (!repoSlugEnv) {
  console.error("REPO env is required");
  process.exit(1);
}
const repoSlug: string = repoSlugEnv;

function readPin(file: string): Pin {
  return JSON.parse(readFileSync(file, "utf8")) as Pin;
}

function writePin(file: string, pin: Pin): void {
  writeFileSync(file, JSON.stringify(pin, null, 2) + "\n", "utf8");
}

async function latestStableTag(owner: string, repo: string): Promise<string | null> {
  try {
    const { data } = await octokit.repos.getLatestRelease({ owner, repo });
    if (!data.prerelease && !data.draft) return data.tag_name;
  } catch {
    // some repos do not mark a "latest" release
  }
  const { data: releases } = await octokit.repos.listReleases({
    owner, repo, per_page: 30,
  });
  const stable = releases.find((r) => !r.prerelease && !r.draft);
  return stable ? stable.tag_name : null;
}

async function tagSha(owner: string, repo: string, tag: string): Promise<string> {
  const { data: ref } = await octokit.git.getRef({
    owner, repo, ref: `tags/${tag}`,
  });
  if (ref.object.type === "commit") return ref.object.sha;
  const { data: annotated } = await octokit.git.getTag({
    owner, repo, tag_sha: ref.object.sha,
  });
  return annotated.object.sha;
}

function sh(cmd: string, args: string[]): string {
  return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();
}

async function main(): Promise<void> {
  for (const t of targets) {
    const pin = readPin(t.file);
    const latest = await latestStableTag(t.owner, t.repo);
    if (!latest) {
      console.log(`${t.name}: no stable release found, skipping`);
      continue;
    }
    if (latest === pin.ref) {
      console.log(`${t.name}: already on ${latest}`);
      continue;
    }
    const sha = await tagSha(t.owner, t.repo, latest);
    console.log(`${t.name}: ${pin.ref} -> ${latest} (${sha.slice(0, 7)})`);

    const branch = `chore/bump-${t.repo.toLowerCase()}-${latest}`;
    // Bail if the branch (and therefore PR) already exists
    try {
      sh("git", ["ls-remote", "--exit-code", "--heads", "origin", branch]);
      console.log(`${t.name}: branch ${branch} already exists, skipping`);
      continue;
    } catch { /* branch does not exist, proceed */ }

    sh("git", ["checkout", "-B", branch, "origin/main"]);
    writePin(t.file, { ref: latest, sha });
    sh("git", ["add", t.file]);
    sh("git", ["commit", "-m", `chore: bump ${t.name} to ${latest}`]);
    sh("git", ["push", "-u", "origin", branch]);

    const body =
      `Automated bump of ${t.name}.\n\n` +
      `- ref: \`${pin.ref}\` -> \`${latest}\`\n` +
      `- sha: \`${pin.sha}\` -> \`${sha}\`\n\n` +
      `Upstream release: https://github.com/${t.owner}/${t.repo}/releases/tag/${latest}\n\n` +
      `Auto-merge will enable when \`pr-verify\` passes.`;
    sh("gh", ["pr", "create",
      "--title", `chore: bump ${t.name} to ${latest}`,
      "--body",  body,
      "--base",  "main",
      "--head",  branch,
      "--repo",  repoSlug,
    ]);
    sh("gh", ["pr", "merge", "--auto", "--squash", "--repo", repoSlug, branch]);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

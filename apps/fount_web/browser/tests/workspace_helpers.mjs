import {expect} from '@playwright/test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

// A server-rendered LiveView is readable before its event handlers are connected.
// Editing journeys begin only after the main view has joined. Navigation must
// also preserve any submitted event until Phoenix acknowledges its reply.
export async function workspaceReady(page) {
  await expect(page.locator('[data-phx-main]')).toHaveClass(/\bphx-connected\b/);
}

export async function workspaceSettled(page) {
  await expect(page.locator('.phx-click-loading, .phx-submit-loading')).toHaveCount(0);
}

export async function openWorkspace(page, url) {
  await workspaceSettled(page);
  const response = await page.goto(url);
  await workspaceReady(page);
  return response;
}

export async function reloadWorkspace(page) {
  await workspaceSettled(page);
  const response = await page.reload();
  await workspaceReady(page);
  return response;
}

export async function importProject(page, name, source) {
  await openWorkspace(page, '/new');
  await page.locator('input[type=file]').setInputFiles({name: `${name}.fountain`, mimeType: 'text/plain', buffer: Buffer.from(source)});
  await page.getByRole('button', {name: 'Preview import'}).click();
  await expect(page.getByRole('heading', {name: `${name}.fountain`})).toBeVisible();
  await page.getByRole('button', {name: 'Open screenplay'}).click();
  await expect(page).toHaveURL(/\/p\/[^/]+$/);
  await workspaceReady(page);
  return new URL(page.url()).pathname.split('/')[2];
}

// Seed retained deterministic journeys through the supported host API. UX02's
// human brief is exercised separately; historical journey forms are gone.
export function seedTask(key, journey) {
  const code = `owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); {:ok, _} = FountWeb.Launch.create_from_project(owner, project["id"], %{ "journey" => System.fetch_env!("FOUNT_FIXTURE_JOURNEY"), "command_id" => Fount.ID.v4() })`;
  hostFixture(code, {FOUNT_FIXTURE_KEY:key, FOUNT_FIXTURE_JOURNEY:journey});
}

export function hostFixture(code, extraEnv = {}) {
  return execFileSync('mix', ['run', '-e', code], {
    cwd: fileURLToPath(new URL('../..', import.meta.url)),
    env: {...process.env, MIX_ENV:'test', PHX_SERVER:'false', ...extraEnv},
    timeout:60000, encoding:'utf8'
  });
}

export async function createTask(page, key, journey) {
  seedTask(key, journey);
  await openWorkspace(page, `/p/${key}/activity/task-1/setup`);
  await page.getByRole('button', {name: 'Start / resume task'}).click();
}

export function projectRunCount(key) {
  const output=hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); rows = FountWeb.Store.list_project_runs(Fount.Repo, owner, project["id"], limit: 50); IO.puts("FOUNT_FIXTURE_RESULT=" <> Integer.to_string(length(rows)))', {FOUNT_FIXTURE_KEY:key});
  return Number(output.split('FOUNT_FIXTURE_RESULT=').at(-1).trim());
}

export async function openWritingMenu(page, name) {
  await expect(page.locator('.phx-connected')).toBeVisible();
  for (const menu of await page.locator('.writing-actions[open]').all()) {
    if ((await menu.locator(':scope > summary').innerText()) !== name) await menu.locator(':scope > summary').click();
  }
  const menu = page.locator('.writing-actions').filter({has: page.locator('summary', {hasText: new RegExp(`^${name}$`)})});
  if (!(await menu.getAttribute('open') !== null)) await menu.locator(':scope > summary').click();
}

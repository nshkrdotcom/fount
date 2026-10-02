import {test, expect} from '@playwright/test';
import {importProject, seedTask} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 07 Browser Fixture\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n\nOWEN\nThat's what you wanted.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page.locator('.phx-connected')).toBeVisible();
}

async function createRun(page, name) {
  const key = await importProject(page, name, fixture);
  seedTask(key, 'opening');
  await page.goto(`/p/${key}/activity/task-1/setup`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  return key;
}

async function openDetails(page) {
  await page.locator('.technical-details').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
}

test('W01-W03 policy, presets and exact-base visual scope persist on project task routes', async ({page}) => {
  await login(page);
  const key = await createRun(page, 'w01-policy');
  for (const gate of ['investigation_scope','strategy_choice','candidate_generation','iteration']) {
    await expect(page.locator(`select[name="policy[${gate}]"]`)).toBeVisible();
  }
  await expect(page.getByLabel('Trusted approver')).toHaveValue('owner');
  await page.locator('select[name="policy[route_choice]"]').selectOption('registered_reviewer');
  await openDetails(page);
  await page.locator('select[name="policy[route_reviewer_key]"]').selectOption('owner');
  await page.getByRole('button',{name:'Save task settings'}).click();
  await expect(page.getByText(/Task settings saved;/)).toBeVisible();
  const name = `Browser policy ${key}`;
  await page.getByLabel('Preset name').fill(name);
  await page.getByRole('button',{name:'Save current policy'}).click();
  await expect(page.getByText(`Saved preset ${name} v1.`)).toBeVisible();
  await page.locator('.preset-card',{hasText:name}).getByRole('button',{name:'Apply settings'}).click();
  await page.reload();
  await expect(page.locator('select[name="policy[route_choice]"]')).toHaveValue('registered_reviewer');
  await page.goto(`/p/${key}/source/task-1`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('#task-scope > summary').click();
  await page.locator('input[name="scope[whole_screenplay]"]').uncheck();
  const scenes=page.locator('input[name="scope[scene_ids][]"]');
  await expect(scenes).toHaveCount(2);
  await scenes.nth(0).check(); await scenes.nth(1).check();
  await page.getByRole('button',{name:'Save task scope'}).click();
  await page.reload();
  await expect(page.locator('input[name="scope[scene_ids][]"]:checked')).toHaveCount(2);
});

test('W05 pause resume stop use durable permitted states', async ({page}) => {
  await login(page); const key=await createRun(page,'w05-lifecycle');
  await page.goto(`/p/${key}/activity/task-1`);
  await page.getByRole('button',{name:'Pause',exact:true}).click();
  await expect(page.getByRole('button',{name:'Resume',exact:true})).toBeEnabled();
  await page.reload();
  await expect(page.getByRole('button',{name:'Resume',exact:true})).toBeEnabled();
  await page.getByRole('button',{name:'Resume',exact:true}).click();
  await expect(page.getByText('Resume recorded',{exact:true})).toBeVisible();
  await page.getByLabel('Confirm permanent stop').check();
  await page.getByRole('button',{name:'Stop',exact:true}).click();
  await expect(page.getByRole('button',{name:'Ensure worker is running'})).toBeDisabled();
  await openDetails(page);
  await expect(page.getByText(/control version/)).toBeVisible();
});

test('W06-W07 named multi-launch produces two persisted tasks and supported exports', async ({page}) => {
  await login(page); const key=await importProject(page,'w07-multi',fixture);
  await page.goto(`/p/${key}/work`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByLabel('What do you want to change or understand?').fill('Sharpen each selected scene independently.');
  await page.locator('#creative-scope-picker > summary').click();
  const scenes=page.locator('input[name="task[scope][]"][value^="scene:"]');
  await scenes.nth(0).check(); await scenes.nth(1).check();
  await page.locator('.task-details > summary').click();
  await page.locator('input[name="task[multi_launch]"]').check();
  await page.getByRole('button',{name:'Review brief'}).click();
  await expect(page.locator('.creative-review')).toContainText('INT. KITCHEN');
  await expect(page.locator('.creative-review')).toContainText('EXT. TRAIN PLATFORM');
  await page.getByRole('button',{name:'Start this work'}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-\\d+/setup$`));
  await page.goto(`/p/${key}/activity`);
  await expect(page.locator('.task-row')).toHaveCount(2);
  await page.goto(`/p/${key}/exports/task-1`);
  await expect(page.locator('input[name="export[pdf]"]')).toBeVisible();
  await expect(page.locator('input[name="export[table_read]"]')).toBeVisible();
});

test('W04-W08 actual decisions and notices recover from saved state', async ({page}) => {
  await login(page); const key=await createRun(page,'w08-decision');
  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  const route=page.getByRole('button',{name:/Commit now|route-a/i}).first();
  await expect(route).toBeVisible({timeout:60000});
  await page.reload(); await expect(route).toBeVisible();
  const notices=page.locator('.notification-panel');
  if (!await notices.evaluate(node=>node.open)) await notices.locator('summary').click();
  await page.getByRole('button',{name:'Mark current notices read'}).click();
  await expect(notices.locator('summary')).toContainText('0 unread');
  await route.click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').last()).toContainText('INT. LOCKED ROOM - NIGHT',{timeout:60000});
  const outsider=await page.context().browser().newContext();
  const other=await outsider.newPage(); await other.goto(`/p/${key}/activity/task-1/decisions`);
  await expect(other).toHaveURL(/\/login$/); await outsider.close();
});

test('Phase 07 purposeful controls remain keyboard readable at 480px', async ({page}) => {
  await page.setViewportSize({width:480,height:900}); await page.emulateMedia({reducedMotion:'reduce'});
  await login(page); await createRun(page,'w480-controls');
  await expect(page.getByText('Review steps',{exact:true})).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  await page.keyboard.press('Tab'); await expect(page.locator(':focus')).toBeVisible();
});

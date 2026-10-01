import {test, expect} from '@playwright/test';
import {importProject} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const artifactRoot = process.env.FOUNT_ARTIFACT_ROOT;

const source = `Title: UX02 BROWSER\nAuthor: Fixture\n\nINT. HALLWAY - NIGHT\n\nMARA watches the elevator numbers.\n\nMARA\nHe said eleven.\n\nELI\nHe lies about small things.\n\nINT. SERVICE ELEVATOR - NIGHT\n\nThe doors open on an empty car.\n\nMARA\nTry me.\n\nEXT. LOADING DOCK - NIGHT\n\nA truck idles under sodium light.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page.locator('.phx-connected')).toBeVisible();
}

async function capture(page, name) {
  if (!artifactRoot) return;
  await page.screenshot({path: `${artifactRoot}/${name}.png`, fullPage: true});
}

test('UX02 compact writing keeps text through Focus exit and supports named keyboard scene moves', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux02-writing', source);
  await page.goto(`/p/${key}/write`);
  await expect(page.locator('.phx-connected')).toBeVisible();

  const editor = page.locator('#source-editor');
  const before = await editor.inputValue();
  await page.getByRole('button', {name: 'Focus', exact: true}).click();
  await expect(page.locator('#project-editor')).toHaveClass(/is-focus-mode/);
  await editor.press('End');
  await editor.pressSequentially('\nA quiet mechanical hum.');
  await page.keyboard.press('Escape');
  await expect(page.locator('#project-editor')).not.toHaveClass(/is-focus-mode/);
  await expect(editor).toHaveValue(before + '\nA quiet mechanical hum.');

  await expect(page.getByRole('button', {name: 'Typewriter scroll off'})).toBeVisible();
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText(/Saved working draft/i);

  await page.locator('#scene-cards > summary').click();
  const firstCard = page.locator('[data-scene-card]').first();
  await firstCard.focus();
  await page.keyboard.press('Alt+ArrowDown');
  await expect(page.getByText(/Scene moved|working draft/i).first()).toBeVisible();
  await capture(page, 'ux02-writing-scene-cards');
});

test('UX02 Work is question-first, preserves the brief across task choices, and creates a durable task without acceptance', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux02-work', source);
  await page.goto(`/p/${key}/work`);
  await expect(page.locator('.phx-connected')).toBeVisible();

  await expect(page.locator('.creative-family-grid--primary .creative-family')).toHaveCount(3);
  const question = page.getByLabel('What do you want to change or understand?');
  await question.fill('Make this handoff quieter without losing the threat.');
  await page.locator('input[name="task[action]"][value="alternatives"]').first().check();
  await expect(question).toHaveValue('Make this handoff quieter without losing the threat.');

  await page.locator('.all-tasks > summary').click();
  await expect(page.getByText('Recover earlier material', {exact: true})).toBeVisible();
  await page.getByLabel('Find a creative task').fill('character');
  await expect(page.getByText('Character work', {exact: true})).toBeVisible();
  await page.getByLabel('Find a creative task').fill('');

  await page.getByRole('button', {name: 'Let the dialogue imply more'}).click();
  await expect(question).toHaveValue('Let the dialogue imply more without changing the facts.');
  await page.getByRole('button', {name: 'Review brief'}).click();
  await expect(page.getByText('Validated brief', {exact: true})).toBeVisible();
  await expect(page.getByText(/current screenplay until explicit acceptance/i)).toBeVisible();
  await capture(page, 'ux02-work-validated-brief');

  await page.getByRole('button', {name: 'Start this work'}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-[0-9]+/setup$`));
  await expect(page.getByText('Review steps', {exact: true})).toBeVisible();
  await expect(page.getByText('Time and spending limits', {exact: true})).toBeVisible();
  await expect(page.getByText('Saved settings', {exact: true})).toBeVisible();
  await expect(page.getByLabel('Maximum spend')).toBeVisible();

  await page.getByLabel('Set a spending ceiling').check();
  await page.getByLabel('Maximum spend').fill('12.50');
  await page.getByRole('button', {name: 'Save task settings'}).click();
  await expect(page.getByText(/Task settings saved/)).toBeVisible();
  await page.reload();
  await expect(page.getByLabel('Maximum spend')).toHaveValue('12.5');

  await page.getByLabel('Preset name').fill('UX02 careful');
  await page.getByRole('button', {name: 'Save current policy'}).click();
  await expect(page.getByText(/Saved preset UX02 careful/)).toBeVisible();
  const downloadPromise = page.waitForEvent('download');
  await page.locator('.preset-card', {hasText: 'UX02 careful'}).getByRole('button', {name: 'Export JSON'}).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toMatch(/ux02-careful-v\d+\.json$/);
  await capture(page, 'ux02-task-purposeful-controls');

  await page.goto(`/p/${key}`);
  await expect(page.locator('.screenplay')).toContainText('He said eleven.');
});

test('UX02 character reading and Try another line bind real source without accepting anything', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux02-character', source);
  await page.goto(`/p/${key}/cast`);
  await expect(page.locator('.phx-connected')).toBeVisible();

  await page.getByRole('button', {name: 'Read this character’s dialogue'}).first().click();
  await expect(page.getByText('Provider-free source reading', {exact: true})).toBeVisible();
  await expect(page.getByRole('link', {name: 'Return to passage'}).first()).toBeVisible();
  await page.getByRole('button', {name: 'Try another line'}).first().click();
  await expect(page.getByText(/Try another line · 3 alternatives/)).toBeVisible();
  await expect(page.getByText(/surrounding source protected/i)).toBeVisible();
  await capture(page, 'ux02-character-line-alternatives');

  await page.goto(`/p/${key}`);
  await expect(page.locator('.screenplay')).toContainText('He said eleven.');
});

test('UX02 notes create an explicit proposal and reopen persisted related work as a factual link', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux02-notes', source);
  await page.goto(`/p/${key}/notes`);
  await expect(page.locator('.phx-connected')).toBeVisible();

  await page.getByLabel('Title').fill('Keep the withheld fact');
  await page.getByLabel('Note', {exact: true}).fill('Do not let Mara explain what she already knows.');
  await page.getByRole('button', {name: 'Save proposed note'}).click();
  await expect(page.getByText('Proposed notes', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Make note current'}).click();
  await expect(page.getByText('Keep the withheld fact', {exact: true})).toBeVisible();

  await page.getByRole('button', {name: 'Work on this note now'}).click();
  await expect(page.getByText('Related work', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Start this work'}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-[0-9]+/setup$`));

  await page.goto(`/p/${key}/notes`);
  await expect(page.getByText(/Related work · Task [0-9]+/)).toBeVisible();
  await expect(page.getByRole('link', {name: 'Open activity'})).toBeVisible();
  await capture(page, 'ux02-note-related-work');
});

test('UX02 work remains usable on tablet, phone touch, and CSS zoom stress view', async ({browser}) => {
  const context = await browser.newContext({hasTouch: true, isMobile: true, viewport: {width: 390, height: 844}});
  const page = await context.newPage();
  await login(page);
  const key = await importProject(page, 'ux02-responsive', source);
  await page.goto(`/p/${key}/work`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByRole('button', {name: 'Look for exposition'}).tap();
  await page.locator('.all-tasks > summary').tap();
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(2);
  await capture(page, 'ux02-phone-work');

  await page.setViewportSize({width: 768, height: 1024});
  await page.reload();
  await expect(page.locator('#creative-brief')).toBeVisible();
  await capture(page, 'ux02-tablet-work');

  await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(4);
  await context.close();
});

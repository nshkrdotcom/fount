import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 05 Authoring\nAuthor: Zoë\n\nINT. CAFÉ - MORNING\n\nMARA studies the departure board.\n\nMARA\nI can revise this.\n\nEXT. PLATFORM - NIGHT\n\nOWEN waits beside the train.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Owner token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createRun(page, key) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill(`Phase 05 ${key}`);
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption('opening');
  await page.getByLabel('Or Fountain source').fill(fixture);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  return page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
}

test('E01-E03/E07 editor handles Unicode, paste, composition, invalid source, modes, text history and reload recovery', async ({page}) => {
  await page.setViewportSize({width: 480, height: 900});
  await login(page);
  const runId = await createRun(page, `authoring-editor-${Date.now()}`);
  await page.goto(`/runs/${runId}/edit`);

  const source = page.getByLabel('Fountain screenplay source');
  await expect(source).toBeVisible();
  await expect(page.getByText(/Fountain syntax assistance/)).toBeVisible();
  await expect(page.locator('.authoring-grid')).toHaveCSS('grid-template-columns', /[0-9.]+px/);

  const unicode = fixture.replace('I can revise this.', 'I can revise this — café 漢字 🙂.');
  await source.fill(unicode);
  await expect(page.getByText('Unsaved local changes')).toBeVisible({timeout: 2_000});
  await expect(page.locator('[data-authoring-preview]')).toContainText('café 漢字 🙂', {timeout: 3_000});

  await source.evaluate((node) => {
    node.dispatchEvent(new CompositionEvent('compositionstart', {bubbles: true, data: 'é'}));
    node.value += '\n\nNORA\nComposed input.';
    node.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertCompositionText', data: 'é'}));
    node.dispatchEvent(new CompositionEvent('compositionend', {bubbles: true, data: 'é'}));
  });
  await expect(page.locator('[data-authoring-preview]')).toContainText('Composed input.', {timeout: 3_000});

  await source.fill(`${unicode}\n[[unfinished`);
  await expect(page.getByText(/last valid draft/)).toBeVisible({timeout: 3_000});
  await page.getByRole('button', {name: 'Save draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('invalid-saved');
  await page.reload();
  await expect(source).toHaveValue(/\[\[unfinished$/);

  await source.fill(unicode);
  await page.getByRole('button', {name: 'Save draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('saved');
  await source.fill(unicode.replace('café', 'bistro'));
  await page.getByRole('button', {name: 'Undo text'}).click();
  await expect(source).toHaveValue(unicode);
  await page.getByRole('button', {name: 'Redo text'}).click();
  await expect(source).toHaveValue(/bistro/);

  await page.getByRole('button', {name: 'Preview', exact: true}).click();
  await expect(source).not.toBeVisible();
  await page.getByRole('button', {name: 'Split', exact: true}).click();
  await expect(source).toBeVisible();
});

test('E05 two tabs produce recoverable conflict instead of last-write-wins', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const runId = await createRun(first, `authoring-conflict-${Date.now()}`);
  await first.goto(`/runs/${runId}/edit`);

  const second = await context.newPage();
  await second.goto(`/runs/${runId}/edit`);

  await first.getByLabel('Fountain screenplay source').fill(fixture.replace('departure board', 'departure display'));
  await first.getByRole('button', {name: 'Save draft'}).click();
  await expect(first.locator('.authoring-status')).toContainText('saved');

  await second.getByLabel('Fountain screenplay source').fill(fixture.replace('departure board', 'arrival display'));
  await second.getByRole('button', {name: 'Save draft'}).click();
  await expect(second.getByRole('heading', {name: 'Draft conflict'})).toBeVisible();
  await expect(second.getByText(/nothing was overwritten/i)).toBeVisible();
  await second.getByRole('button', {name: /Keep my text/}).click();
  await expect(second.getByText(/separate recovery draft/)).toBeVisible();
  await expect(second.getByLabel('Fountain screenplay source')).toHaveValue(/arrival display/);
  await context.close();
});

test('E04-E06 candidate save leaves canon unchanged, AI uses Run, and acceptance is separate', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `authoring-candidate-${Date.now()}`);
  await page.goto(`/runs/${runId}/edit`);
  const source = page.getByLabel('Fountain screenplay source');
  const edited = fixture.replace('departure board', 'blue departure board');
  await source.fill(edited);
  await page.getByRole('button', {name: 'Save draft'}).click();
  await page.getByRole('button', {name: 'Save candidate'}).click();
  await expect(page.getByText(/Canon is unchanged/)).toBeVisible();

  await page.goto(`/runs/${runId}/viewer`);
  await expect(page.locator('.screenplay')).toContainText('departure board');
  await expect(page.locator('.screenplay')).not.toContainText('blue departure board');

  await page.goto(`/runs/${runId}/edit`);
  await page.getByRole('button', {name: 'AI assist via Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/timeline$/);
  await expect(page.getByText(/candidate/i).first()).toBeVisible();

  await page.goto(`/runs/${runId}/edit`);
  await page.getByRole('button', {name: 'Accept exact candidate'}).click();
  await expect(page.getByText(/canonical head advanced/)).toBeVisible();
  await page.goto(`/runs/${runId}/viewer`);
  await expect(page.locator('.screenplay')).toContainText('blue departure board');
});

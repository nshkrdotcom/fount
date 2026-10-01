import {test, expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {importProject, projectRunCount, seedTask} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const artifactRoot = process.env.FOUNT_ARTIFACT_ROOT;

const source = `Title: UX03 BROWSER\nAuthor: Fixture\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board, one hand around a brass key.\n\nNORA\nThe train is late.\n\nOWEN\nThat's what you wanted.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;

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

async function noHorizontalOverflow(page) {
  return page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1);
}

test('UX03 Reading is calm, exact search is source-bound, and narrow comparison uses tabs', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-reading', source);

  await page.goto(`/p/${key}`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.getByRole('navigation', {name: 'Reading actions'})).toContainText('Notes');
  await expect(page.getByRole('navigation', {name: 'Reading actions'})).toContainText('Export');
  await expect(page.locator('main')).not.toContainText('Settings');
  await expect(page.locator('#about-screenplay')).not.toHaveAttribute('open', '');

  await page.locator('#script-search > summary').click();
  await page.getByLabel('Literal text').fill('coffee maker');
  await page.getByLabel('Maximum results').fill('1');
  await page.getByRole('button', {name: 'Search selected source'}).click();
  await expect(page.locator('.script-search-results')).toContainText('1 result(s)');
  await expect(page.locator('.script-search-results')).toContainText('coffee maker');
  await expect(page.locator('.script-search-results')).toContainText(/Inspected \d+ eligible source elements/);
  await capture(page, 'ux03-reading-literal-search');

  await page.goto(`/p/${key}/write`);
  const editor = page.locator('#source-editor');
  await editor.fill((await editor.inputValue()) + '\n\nMARA\nKeep the light off.');
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText(/Saved working draft/i);

  await page.goto(`/p/${key}`);
  await page.getByRole('link', {name: 'Working draft'}).click();
  await expect(page.locator('#source-comparison')).toBeVisible();
  await page.setViewportSize({width: 390, height: 844});
  await expect(page.locator('.source-comparison__tabs')).toBeVisible();
  await page.locator('label[for="compare-proposed"]').click();
  await expect(page.locator('.source-comparison__panel--proposed')).toBeVisible();
  await page.locator('label[for="compare-changes"]').click();
  await expect(page.locator('.source-comparison__panel--changes')).toBeVisible();
  await expect(page.locator('[data-compare-count]')).toContainText(/Change|No structural changes/);
  expect(await noHorizontalOverflow(page)).toBe(true);
  await capture(page, 'ux03-phone-source-comparison');
  expect(projectRunCount(key)).toBe(0);
});

test('UX03 reading text selection opens Notes with the exact current passage preselected', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-selection-note', source);
  await page.goto(`/p/${key}`);
  const passage = page.locator('.screenplay-element__text', {hasText: 'coffee maker'}).first();
  await passage.evaluate((element) => {
    const range = document.createRange();
    range.selectNodeContents(element);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    element.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
  });
  const noteButton = page.getByRole('button', {name: 'Note selected passage'});
  await expect(noteButton).toBeEnabled();
  await noteButton.click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/notes\\?`));
  await expect(page.getByText(/Selected passage carried into this note/)).toBeVisible();
  await expect(page.locator('select[name="note[target]"] option:checked')).toContainText('coffee maker');
  expect(projectRunCount(key)).toBe(0);
});

test('UX03 notes support exact remap search, human response history, and immediate memo preview', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-notes', source);
  await page.goto(`/p/${key}/notes`);
  await expect(page.locator('.phx-connected')).toBeVisible();

  await page.getByLabel('Title').fill('Keep the withheld fact');
  await page.getByLabel('Note', {exact: true}).fill('Keep this exact wording.');
  await page.getByRole('button', {name: 'Save proposed note'}).click();
  await page.getByRole('button', {name: 'Make this note change current'}).click();
  await expect(page.getByText('Keep the withheld fact', {exact: true})).toBeVisible();

  await page.getByLabel('Exact literal search').fill('coffee maker');
  await page.getByRole('button', {name: 'Find passages'}).click();
  await expect(page.locator('.compact-results')).toContainText('coffee maker');

  const note = page.locator('.note-card', {hasText: 'Keep the withheld fact'});
  await note.getByLabel('Response').selectOption('addressed');
  await note.getByLabel('Comment').fill('Handled in the exact current revision.');
  await note.getByRole('button', {name: 'Save reviewer response'}).click();
  await expect(page.getByRole('status')).toContainText(/Reviewer response saved/i);

  await page.locator('input[name="memo[note_ids][]"]').first().check();
  await page.getByLabel('From').fill('A. Reader');
  await page.getByLabel('To').fill('Writer');
  await page.getByLabel('Include actual saved reviewer responses').check();
  await page.getByRole('button', {name: 'Build notes memo'}).click();
  await expect(page.getByRole('heading', {name: 'Built notes memos'})).toBeVisible();
  const previewHref = await page.getByRole('link', {name: 'Preview memo'}).first().getAttribute('href');
  expect(previewHref).toBeTruthy();
  await page.goto(previewHref);
  await expect(page.locator('body')).toContainText('Keep this exact wording.');
  await expect(page.locator('body')).toContainText('Reviewer response: addressed');
  await expect(page.locator('body')).toContainText('Handled in the exact current revision.');
});

test('UX03 cast/location facts and manual table read remain provider-free and create no Run', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-read', source);

  await page.goto(`/p/${key}/cast`);
  await expect(page.getByRole('heading', {name: 'Cast & locations'})).toBeVisible();
  await expect(page.locator('.character-grid')).toContainText('dialogue blocks');
  await expect(page.locator('.location-list')).toContainText('KITCHEN');
  const rename = page.locator('form[phx-submit="preview_cast_rename"]').first();
  await rename.getByLabel('Prepare name change').fill('MARA VALE');
  await rename.getByRole('button', {name: 'Preview affected source'}).click();
  await expect(page.getByText('Proposed name change', {exact: true})).toBeVisible();
  await expect(page.locator('.creative-review')).toContainText('confirmed cue edits');

  await page.goto(`/p/${key}/read`);
  await page.locator('select[name="read[scope][]"]').selectOption(['whole']);
  await page.getByRole('button', {name: 'Save table-read material'}).click();
  await expect(page.locator('#table-read-workspace')).toBeVisible();
  await expect(page.locator('#table-read-workspace')).toContainText(/Unavailable|Available/);
  const firstTurn = page.locator('[data-read-turn]').first();
  await firstTurn.focus();
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-read-turn]').nth(1)).toHaveClass(/is-active-read-turn/);
  await page.getByRole('button', {name: 'Bookmark current passage'}).click();
  await page.getByLabel('Reader').fill('Nora reader');
  await page.getByLabel('Reaction').fill('The pause landed without a performance score.');
  await page.getByRole('button', {name: 'Save reaction'}).click();
  await expect(page.locator('.reaction-list')).toContainText('The pause landed');

  await page.emulateMedia({reducedMotion: 'reduce'});
  await page.reload();
  await page.locator('.saved-read-row').first().click();
  await expect(page.getByRole('button', {name: 'Start / pause'})).toBeDisabled();
  await expect(page.getByRole('button', {name: 'Previous'})).toBeEnabled();
  await expect(page.getByRole('button', {name: 'Next'})).toBeEnabled();
  await capture(page, 'ux03-table-read-reduced-motion');
  expect(projectRunCount(key)).toBe(0);
});

test('UX03 table-read two-tab conflict reloads saved human state instead of overwriting it', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const key = await importProject(first, 'ux03-read-conflict', source);
  await first.goto(`/p/${key}/read`);
  await first.locator('select[name="read[scope][]"]').selectOption(['whole']);
  await first.getByRole('button', {name: 'Save table-read material'}).click();

  const second = await context.newPage();
  await second.goto(`/p/${key}/read`);
  await expect(second.locator('.phx-connected')).toBeVisible();
  await second.locator('.saved-read-row').first().click();

  await first.getByRole('button', {name: 'Bookmark current passage'}).click();
  await first.waitForTimeout(250);
  await second.getByRole('button', {name: 'Bookmark current passage'}).click();
  await expect(second.getByRole('alert')).toContainText(/changed in another tab/i);
  await expect(second.locator('#table-read-workspace')).toBeVisible();
  expect(projectRunCount(key)).toBe(0);
  await context.close();
});

test('UX03 optional feedback stays attached to a real task and keeps independent dimensions', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-feedback', source);
  seedTask(key, 'dialogue');
  await page.goto(`/p/${key}/activity/task-1/setup`);
  await page.getByRole('button', {name: 'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button', {name: 'Commit now', exact: true}).click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.', {timeout: 60_000});

  await page.goto(`/p/${key}/feedback`);
  await expect(page.getByRole('heading', {name: 'Feedback'})).toBeVisible();
  const form = page.locator('.feedback-form').first();
  await form.getByLabel('Useful', {exact: true}).check();
  await form.getByLabel('I kept my original').check();
  const voice = form.getByText(/Did this keep the character’s voice/);
  if (await voice.count()) await form.getByLabel('Partly', {exact: true}).first().check();
  await form.getByLabel('Notes').fill('Useful for comparison, but I kept the original.');
  await form.locator('details > summary', {hasText: 'More detail'}).click();
  await form.getByLabel('Task completion').fill('It made the tradeoff clear.');
  await form.getByRole('button', {name: 'Save optional feedback'}).click();
  await expect(page.getByRole('heading', {name: 'Saved responses'})).toBeVisible();
  await expect(page.locator('.feedback-report')).toContainText(/No combined quality, learning or preference score/);
  await page.reload();
  const reopened = page.locator('.feedback-form').first();
  await expect(reopened.getByLabel('Useful', {exact: true})).toBeChecked();
  await expect(reopened.getByLabel('I kept my original')).toBeChecked();
  await expect(reopened.getByLabel('Notes')).toHaveValue('Useful for comparison, but I kept the original.');
  await expect(reopened.getByRole('button', {name: 'Update optional feedback'})).toBeVisible();
  await capture(page, 'ux03-feedback-independent-dimensions');
});

test('UX03 exact Fountain, FDX and PDF exports preview/download from the named current revision', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-exports', source);
  await page.goto(`/p/${key}/exports`);
  await expect(page.getByRole('heading', {name: 'Exports'})).toBeVisible();

  await page.getByRole('button', {name: 'Build Fountain'}).click();
  await expect(page.locator('.artifact-row').first()).toContainText('.fountain');
  const fountainPreview = await page.getByRole('link', {name: 'Preview'}).first().getAttribute('href');
  await page.goto(fountainPreview);
  await expect(page.locator('body')).toContainText('coffee maker');

  await page.goto(`/p/${key}/exports`);
  await page.getByRole('button', {name: 'Build FDX'}).click();
  await expect(page.locator('.artifact-list')).toContainText('.fdx');

  await page.getByRole('button', {name: 'Build PDF'}).click();
  await expect(page.getByRole('link', {name: 'Read numbered PDF pages'}).first()).toBeVisible({timeout: 60000});
  await page.getByRole('link', {name: 'Read numbered PDF pages'}).first().click();
  await expect(page.getByRole('heading', {name: 'Exported pages'})).toBeVisible();
  await expect(page.getByTitle(/exported PDF page 1/)).toBeVisible();
  await expect(page.getByText(/No responsive-screenplay coordinate is presented as a PDF page mapping/)).toBeVisible();
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('link', {name: 'Download PDF'}).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toMatch(/\.pdf$/);
  const bytes = readFileSync(await download.path());
  expect(bytes.subarray(0, 5).toString()).toBe('%PDF-');
  await capture(page, 'ux03-exported-pdf-pages');
});

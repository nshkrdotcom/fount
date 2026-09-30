import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fountain = `Title: Phase 08 Browser\nAuthor: Fount\n\nINT. CAFÉ - MORNING\n\nMARA puts the café receipt beside the coffee maker.\n\nMARA\nThe café opens before dawn.\n\nOWEN\nCount it twice.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nMARA waits under the departure board.\n\nMARA\nThe receipt is still in my pocket.\n`;
const fdx = `<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>INT. FDX ROOM - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Mara checks the imported page.</Text></Paragraph><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>The import is visible.</Text></Paragraph></Content><TagData/></FinalDraft>`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createRun(page, key, options = {}) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill(options.title || 'Phase 08 Browser');
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption('opening');
  if (options.synopsis) await page.getByLabel(/Supplied synopsis/).fill(options.synopsis);
  if (options.thumbnail) await page.getByLabel(/Supplied thumbnail reference/).fill(options.thumbnail);
  await page.getByLabel('Or Fountain source').fill(options.source || fountain);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  return page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
}

async function openSection(page, runId, section) {
  await page.goto(`/runs/${runId}/tools?section=${section}`);
  await expect(page.getByRole('navigation', {name: 'Production tool sections'})).toBeVisible();
}

test('S01-S03 literal retrieval, cast facts and location inspection stay bound to the selected revision', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `s01-${Date.now()}`);
  await openSection(page, runId, 'search');

  const revision = await page.locator('.production-mast code').nth(1).textContent();
  await page.getByLabel('Literal phrase').fill('café');
  await page.getByLabel('Limit').fill('1');
  await page.getByRole('button', {name: 'Search selected revision'}).click();
  await expect(page.getByText(/Inspected .* returned 1/)).toBeVisible();
  await expect(page.getByText(/Truncated at the requested limit/)).toBeVisible();
  const source = page.getByRole('link', {name: 'Open exact source element'}).first();
  await expect(source).toHaveAttribute('href', new RegExp(`view=.*${revision.slice(0, 8)}`));
  await source.click();
  await expect(page).toHaveURL(new RegExp(`/viewer\\?view=.*#node-`));

  await openSection(page, runId, 'cast');
  await expect(page.getByRole('heading', {name: 'Character profiles'})).toBeVisible();
  await expect(page.getByText(/Confirmed mentions/).first()).toBeVisible();
  await expect(page.getByText(/do not infer biography, emotional arc or screenplay quality/)).toBeVisible();

  await openSection(page, runId, 'locations');
  await expect(page.getByRole('heading', {name: 'Locations and scene order'})).toBeVisible();
  await expect(page.getByText('CAFÉ', {exact: true})).toBeVisible();
  await expect(page.getByText(/derived reading approximation/).first()).toBeVisible();
  await expect(page.getByText(/not shooting schedules or production plans/)).toBeVisible();
});

test('S04 note changes are durable candidates, separate from annotations, and exact approval is a distinct canon action', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `s04-${Date.now()}`);
  await openSection(page, runId, 'notes');

  await expect(page.getByText(/Measured annotations are separate evidence/)).toBeVisible();
  await page.getByLabel('Title').first().fill('Continuity');
  await page.getByRole('textbox', {name: 'Note', exact: true}).fill('Keep the receipt visible.');
  await page.getByRole('button', {name: 'Save note candidate'}).click();
  await expect(page.getByText(/The approved screenplay is unchanged until you approve/)).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Pending production-tool candidates'})).toBeVisible();
  await page.getByRole('button', {name: 'Exact approve'}).click();
  await expect(page.getByText(/Candidate accepted as revision/)).toBeVisible();
  await expect(page.getByRole('paragraph').filter({hasText: /^Keep the receipt visible\.$/})).toBeVisible();
  await expect(page.locator('.note-card[data-note-state="active"] code').first()).toBeVisible();

  const exportLink = page.getByRole('link', {name: /Export notes JSON/});
  const href = await exportLink.getAttribute('href');
  const body = await page.evaluate(async url => (await fetch(url, {credentials: 'same-origin'})).json(), href);
  expect(body.kind).toBe('fount.authored_notes_export');
  expect(body.notes.some(note => note.text === 'Keep the receipt visible.')).toBeTruthy();

  const searchUrl = new URL(page.url());
  searchUrl.searchParams.set('section', 'search');
  await page.goto(searchUrl.toString());
  await page.getByLabel('Literal phrase').fill('receipt');
  await page.getByRole('button', {name: 'Search selected revision'}).click();
  await expect(page.locator('.search-hits li').first()).toBeVisible();
  const base = await page.getByRole('combobox', {name: /^Screenplay version/}).locator('option').filter({hasText: 'Run base'}).getAttribute('value');
  await page.getByRole('combobox', {name: /^Screenplay version/}).selectOption(base);
  await expect(page.getByText('Search cleared because the exact revision changed.')).toBeVisible();
  await expect(page.locator('.search-hits li')).toHaveCount(0);
});

test('S05-S06 human table read state and descriptive usefulness evidence persist without quality scoring', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `s56-${Date.now()}`);
  await openSection(page, runId, 'read');

  await expect(page.getByText(/optional TTS is not configured/)).toBeVisible();
  await page.getByRole('button', {name: 'Save read packet'}).click();
  const read = page.locator('#table-read-workspace');
  await expect(read).toBeVisible();
  await expect(read.locator('[data-read-turn]')).not.toHaveCount(0);
  await read.locator('[data-read-turns]').evaluate(node => {
    node.style.height = '36px';
    node.style.overflowY = 'auto';
  });
  await read.getByRole('button', {name: 'Auto-scroll'}).click();
  await expect.poll(async () => Number(await read.getAttribute('data-version'))).toBeGreaterThan(1);
  await page.waitForTimeout(120);
  await read.getByRole('button', {name: 'Pause'}).click();
  await expect.poll(async () => Number(await read.getAttribute('data-version'))).toBeGreaterThan(2);
  expect(Number(await read.locator('[data-read-elapsed]').textContent())).toBeGreaterThan(0);
  await read.locator('[data-read-turn]').nth(1).focus();
  await page.keyboard.press('Enter');
  await expect(read.locator('[data-read-turn]').nth(1)).toHaveClass(/is-active-read-turn/);
  await read.getByRole('button', {name: 'Bookmark active turn'}).click();
  await expect.poll(async () => Number(await read.getAttribute('data-version'))).toBeGreaterThan(3);
  await page.reload();
  await expect(page.locator('#table-read-workspace')).toHaveAttribute('data-bookmark', '1');
  await page.getByLabel('Reader label').fill('reader-a');
  await page.getByLabel('Human reaction').fill('The handoff landed clearly.');
  await page.getByRole('button', {name: 'Save human reaction'}).click();
  await expect(page.getByText(/reader-a: The handoff landed clearly/)).toBeVisible();

  await openSection(page, runId, 'usefulness');
  await page.getByLabel('Task ID').fill('browser-task');
  await page.getByLabel('Condition').selectOption('fount_assisted');
  await page.getByLabel('Outcome').selectOption('neutral');
  await page.getByText('Kept original').locator('input').check();
  await page.getByLabel(/Preference/).fill('original');
  await page.getByLabel('Agency').fill('high');
  await page.getByLabel('Rejection time (ms)').fill('420');
  await page.getByRole('button', {name: 'Save descriptive record'}).click();
  await expect(page.getByText(/1 saved human response; no representativeness claim/)).toBeVisible();
  await expect(page.getByText(/No aggregate screenplay score, winner, expert endorsement/)).toBeVisible();
  await expect(page.getByText(/kept original/).last()).toBeVisible();
});

test('S07 dashboard preserves supplied metadata and reports Fountain/FDX fidelity without generating synopsis or thumbnails', async ({page}) => {
  await login(page);
  const key = `s07-fountain-${Date.now()}`;
  await createRun(page, key, {synopsis: 'Writer supplied synopsis.', thumbnail: 'writer://thumb/phase08'});
  await page.goto('/');
  const card = page.locator('.project-card').filter({hasText: key});
  await expect(card).toContainText('Writer supplied synopsis.');
  await expect(card).toContainText('writer://thumb/phase08');
  await expect(card).toContainText(/Import: fountain/);
  await expect(card).toContainText(/losses 0/);
  await expect(card.getByRole('link', {name: 'Search & production tools'})).toBeVisible();

  await page.goto('/projects/new');
  const fdxKey = `s07-fdx-${Date.now()}`;
  await page.getByLabel('Project title').fill('FDX browser import');
  await page.getByLabel('Project key').fill(fdxKey);
  await page.getByLabel('Journey').selectOption('opening');
  await page.getByLabel('Upload Fountain/FDX (max 1 MiB)').setInputFiles({
    name: 'phase08.fdx',
    mimeType: 'application/xml',
    buffer: Buffer.from(fdx),
  });
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  await page.goto('/');
  const fdxCard = page.locator('.project-card').filter({hasText: fdxKey});
  await expect(fdxCard).toContainText(/Import: fdx/);
  await expect(fdxCard).toContainText(/accepted revision/);

  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByLabel('Filter projects').fill(fdxKey);
  await expect(page.locator('.project-card')).toHaveCount(1);
  await page.getByLabel('Sort').selectOption('scenes');
  await expect(page.locator('.project-card')).toHaveCount(1);
});

for (const viewport of [
  {name: 'desktop', width: 1440, height: 900},
  {name: 'tablet', width: 900, height: 1000},
  {name: 'phone', width: 480, height: 900},
]) {
  test(`S08 ${viewport.name} tools remain keyboard/focus/zoom/reconnect usable`, async ({page}) => {
    await page.setViewportSize({width: viewport.width, height: viewport.height});
    await login(page);
    const runId = await createRun(page, `s08-${viewport.name}-${Date.now()}`);
    await openSection(page, runId, 'search');
    await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(3);
    await page.keyboard.press('Tab');
    await expect(page.locator(':focus')).toBeVisible();
    await page.evaluate(() => window.liveSocket.disconnect());
    await page.evaluate(() => window.liveSocket.connect());
    await expect(page.getByRole('heading', {name: 'Search this screenplay version'})).toBeVisible();

    await openSection(page, runId, 'read');
    await page.getByRole('button', {name: 'Save read packet'}).click();
    const read = page.locator('#table-read-workspace');
    await expect(read).toBeVisible();
    await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(3);
    const clipped = await read.locator('button').evaluateAll(nodes => nodes.some(node => {
      const rect = node.getBoundingClientRect();
      return rect.left < -2 || rect.right > document.documentElement.clientWidth + 2;
    }));
    expect(clipped).toBeFalsy();
  });
}

test('S08 reduced motion disables automatic table-read scrolling while manual controls remain available', async ({page}) => {
  await page.emulateMedia({reducedMotion: 'reduce'});
  await login(page);
  const runId = await createRun(page, `s08-motion-${Date.now()}`);
  await openSection(page, runId, 'read');
  await page.getByRole('button', {name: 'Save read packet'}).click();
  const read = page.locator('#table-read-workspace');
  await expect(read.getByRole('button', {name: 'Auto-scroll'})).toBeDisabled();
  await expect(read.getByRole('button', {name: 'Bookmark active turn'})).toBeEnabled();
  await read.locator('[data-read-turn]').first().focus();
  await page.keyboard.press('Enter');
  await expect(read.locator('[data-read-turn]').first()).toHaveClass(/is-active-read-turn/);
});


test('S05 two tabs recover persisted table-read state after an optimistic conflict', async ({page, context}) => {
  await login(page);
  const runId = await createRun(page, `s05-conflict-${Date.now()}`);
  await openSection(page, runId, 'read');
  await page.getByRole('button', {name: 'Save read packet'}).click();
  const firstRead = page.locator('#table-read-workspace');
  await expect(firstRead).toBeVisible();
  const second = await context.newPage();
  await openSection(second, runId, 'read');
  const secondRead = second.locator('#table-read-workspace');
  await expect(second.locator('.phx-connected')).toBeVisible();
  await expect(secondRead).toHaveAttribute('data-version', '1');

  await firstRead.locator('[data-read-turn]').nth(1).focus();
  await page.keyboard.press('Enter');
  await firstRead.getByRole('button', {name: 'Bookmark active turn'}).click();
  await expect(firstRead).toHaveAttribute('data-version', '2');
  await secondRead.getByRole('button', {name: 'Bookmark active turn'}).click();
  await expect(second.getByText('Table-read state changed in another tab; loaded the saved state.')).toBeVisible();
  await expect(secondRead).toHaveAttribute('data-version', '2');
  await expect(secondRead).toHaveAttribute('data-bookmark', '1');
  await secondRead.locator('[data-read-turn]').nth(2).focus();
  await second.keyboard.press('Enter');
  await secondRead.getByRole('button', {name: 'Bookmark active turn'}).click();
  await expect(secondRead).toHaveAttribute('data-version', '3');
  await second.reload();
  await expect(secondRead).toHaveAttribute('data-bookmark', '2');
  await second.close();
});

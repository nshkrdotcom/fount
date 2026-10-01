import {test, expect} from '@playwright/test';
import {importProject} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 05 Authoring\nAuthor: Zoë\n\nINT. CAFÉ - MORNING\n\nMARA studies the departure board.\n\nMARA\nI can revise this.\n\nEXT. PLATFORM - NIGHT\n\nOWEN waits beside the train.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('.phx-connected')).toBeVisible();
}

async function createRun(page, key) {
  return importProject(page, key, fixture);
}

test('E01-E03/E07 editor handles Unicode, paste, composition, invalid source, modes, text history and reload recovery', async ({page}) => {
  await page.setViewportSize({width: 480, height: 900});
  await login(page);
  const runId = await createRun(page, `authoring-editor-${Date.now()}`);
  await page.goto(`/p/${runId}/write`);

  const source = page.getByLabel('Fountain screenplay source');
  await expect(source).toBeVisible();
  await expect(page.getByText(/Plain Fountain text/)).toBeVisible();
  expect(await page.locator('.authoring-grid').evaluate(node => node.scrollWidth <= node.clientWidth + 2)).toBe(true);

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
  await expect(page.locator('#authoring-diagnostics')).not.toContainText('raw text is still saved');
  await expect(page.getByText(/last valid draft/)).toBeVisible({timeout: 3_000});
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Fountain needs attention');
  await page.reload();
  await expect(source).toHaveValue(/\[\[unfinished$/);

  await source.fill(unicode);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  await source.fill(unicode.replace('café', 'bistro'));
  await page.locator('#text-history summary').click();
  await page.getByRole('button', {name: 'Undo text'}).click();
  await expect(source).toHaveValue(unicode);
  await page.getByRole('button', {name: 'Redo text'}).click();
  await expect(source).toHaveValue(/bistro/);

  await page.getByRole('button', {name: 'Pages', exact: true}).click();
  await expect(source).not.toBeVisible();
  await page.getByRole('button', {name: 'Source + pages', exact: true}).click();
  await expect(source).toBeVisible();
});

test('E05 two tabs produce recoverable conflict instead of last-write-wins', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const runId = await createRun(first, `authoring-conflict-${Date.now()}`);
  await first.goto(`/p/${runId}/write`);

  const second = await context.newPage();
  await second.goto(`/p/${runId}/write`);
  await expect(second.locator('.phx-connected')).toBeVisible();

  await first.getByLabel('Fountain screenplay source').fill(fixture.replace('departure board', 'departure display'));
  await first.getByRole('button', {name: 'Save working draft'}).click();
  await expect(first.locator('.authoring-status')).toContainText('Saved working draft');

  await second.getByLabel('Fountain screenplay source').fill(fixture.replace('departure board', 'arrival display'));
  await second.getByRole('button', {name: 'Save working draft'}).click();
  await expect(second.getByRole('heading', {name: 'This draft changed in another tab'})).toBeVisible();
  await expect(second.getByText(/nothing was overwritten/i)).toBeVisible();
  await second.getByRole('button', {name: /Keep my text/}).click();
  await expect(second.getByText(/separate recovery draft/)).toBeVisible();
  await expect(second.getByLabel('Fountain screenplay source')).toHaveValue(/arrival display/);
  await context.close();
});

test('E04-E06 candidate save leaves canon unchanged, creative work uses Run, and acceptance is separate', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `authoring-candidate-${Date.now()}`);
  await page.goto(`/p/${runId}/write`);
  const source = page.getByLabel('Fountain screenplay source');
  const edited = fixture.replace('departure board', 'blue departure board');
  await source.fill(edited);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await page.getByRole('button', {name: 'Save proposed change'}).click();
  await expect(page.getByText(/The current screenplay is unchanged/)).toBeVisible();

  await page.goto(`/p/${runId}`);
  await expect(page.locator('.screenplay')).toContainText('departure board');
  await expect(page.locator('.screenplay')).not.toContainText('blue departure board');

  await page.goto(`/p/${runId}/work`);
  await page.getByLabel('What do you want to change or understand?').fill('Tighten the opening beat without changing its facts.');
  await page.getByRole('button', {name: 'Review brief'}).click();
  await expect(page.getByText('Validated brief', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Start this work'}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${runId}/activity/task-1/setup$`));
  const aiRunId = 'task-1';
  await page.goto(`/p/${runId}/activity/${aiRunId}/decisions`);
  const route = page.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(route).toBeVisible({timeout: 60_000});
  await route.click();
  await page.goto(`/p/${runId}/changes/${aiRunId}`);
  await expect(page.locator('pre.script').last()).toContainText('INT. LOCKED ROOM - NIGHT', {timeout: 60_000});
  await expect(page.locator('pre.script').first()).toContainText('departure board');
  await expect(page.locator('p.status')).toContainText('stage: decide', {timeout: 60_000});
  await expect(page.getByRole('heading', {name: /Analysis before writing/i})).toBeVisible();
  await page.goto(`/p/${runId}/activity/${aiRunId}/decisions`);
  await expect(page.getByRole('button', {name: 'Rebase candidate onto current canon'})).toBeVisible();
  await page.getByLabel('Confirm permanent stop').check();
  await page.getByRole('button', {name: 'Stop this run'}).click();
  await expect(page.locator('p.status')).toContainText('stopped');
  await page.goto(`/p/${runId}`);
  await expect(page.locator('.screenplay')).not.toContainText('blue departure board');

  await page.goto(`/p/${runId}/write`);
  await page.getByRole('button', {name: 'Make proposed change current'}).click();
  await expect(page.getByText(/Revision approved and saved/)).toBeVisible();
  await expect(source).toHaveAttribute('readonly', '');
  await page.goto(`/p/${runId}`);
  await expect(page.locator('.screenplay')).toContainText('blue departure board');
  await page.goto(`/p/${runId}/write`);
  await expect(page.getByLabel('Fountain screenplay source')).toHaveValue(edited);
});

test('E01/E02/E03/E07 debounce, ordered replies, history bounds, focus, dirty warning and client-cache isolation', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `authoring-lifecycle-${Date.now()}`);
  await page.goto(`/p/${runId}/write`);
  const source = page.getByLabel('Fountain screenplay source');
  await expect(source).toBeVisible();
  await page.waitForFunction(() => Object.values(window.liveSocket.roots)[0]?.getHook(document.querySelector('[phx-hook="AuthoringEditor"]')));
  await page.evaluate(() => {
    const hook = Object.values(window.liveSocket.roots)[0].getHook(document.querySelector('[phx-hook="AuthoringEditor"]'));
    window.qcPreviewEvents = [];
    const push = hook.pushEvent.bind(hook);
    hook.pushEvent = (name, payload, ...rest) => {
      if (name === 'preview_source') window.qcPreviewEvents.push({at: performance.now(), seq: payload.client_seq});
      return push(name, payload, ...rest);
    };
  });
  const raw = fixture.replace('I can revise this.', 'Unicode — café 漢字 🙂 <script>window.qcInjected=true</script>.');
  await source.fill(raw);
  const idleAt = await page.evaluate(() => performance.now());
  await expect(page.locator('[data-authoring-preview]')).toContainText('Unicode — café 漢字 🙂');
  const timing = await page.evaluate(() => window.qcPreviewEvents);
  expect(timing).toHaveLength(1);
  expect(timing[0].at - idleAt).toBeGreaterThan(150);
  expect(timing[0].at - idleAt).toBeLessThan(1500);
  console.log(`E02 reference idle preview push: ${Math.round(timing[0].at - idleAt)} ms; events=${timing.length}`);
  expect(await page.evaluate(() => window.qcInjected)).toBeUndefined();
  expect(await page.locator('[data-authoring-preview] script').count()).toBe(0);
  await source.focus();
  await source.evaluate(node => node.setSelectionRange(12, 17));
  for (let n = 0; n < 3; n++) {
    await page.getByRole('button', {name: 'Source', exact: true}).click();
    await page.getByRole('button', {name: 'Pages', exact: true}).click();
    await page.getByRole('button', {name: 'Source + pages', exact: true}).click();
  }
  await expect(source).toHaveValue(raw);
  expect(await source.evaluate(node => [node.selectionStart, node.selectionEnd])).toEqual([12, 17]);
  await source.focus();
  await source.press('Control+z');
  await expect(source).toHaveValue(fixture);
  await source.press('Control+Shift+z');
  await expect(source).toHaveValue(raw);
  await source.press('Control+z');
  await source.press('Control+y');
  await expect(source).toHaveValue(raw);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('phx:authoring:replace_source', {detail: {source: 'LATE REPLACEMENT', expected_client_seq: 0}})));
  await expect(source).toHaveValue(raw);
  await expect(page.getByText(/newer local edit prevented/)).toBeVisible();
  const blocked = await page.evaluate(() => !window.dispatchEvent(new Event('beforeunload', {cancelable: true})));
  expect(blocked).toBe(true);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  expect(await page.evaluate(() => !window.dispatchEvent(new Event('beforeunload', {cancelable: true})))).toBe(false);
  await page.evaluate(() => {
    const hook = Object.values(window.liveSocket.roots)[0].getHook(document.querySelector('[phx-hook="AuthoringEditor"]'));
    for (let n = 0; n < 110; n++) {
      hook.source.value += `\nHistory ${n}.`;
      hook.source.dispatchEvent(new Event('input', {bubbles: true}));
    }
  });
  expect(await page.evaluate(() => Object.values(window.liveSocket.roots)[0].getHook(document.querySelector('[phx-hook="AuthoringEditor"]')).textHistory.length)).toBe(100);
  await expect(page.locator('.authoring-status')).toContainText('Unsaved local changes');
  expect(await page.evaluate(() => Object.values(localStorage).concat(Object.values(sessionStorage)).some(value => value.includes('INT. CAFÉ')))).toBe(false);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  await page.evaluate(() => window.liveSocket.disconnect());
  await page.evaluate(() => window.liveSocket.connect());
  await page.reload();
  await expect(source).toHaveValue(/History 109\./);
  const width = await page.evaluate(() => ({width: innerWidth, scroll: document.documentElement.scrollWidth}));
  expect(width.scroll).toBeLessThanOrEqual(width.width + 2);
});

test('E05/E07 lost acknowledgement retry, newer-server recovery and invalid interrupted draft reload', async ({browser}) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await login(page);
  const runId = await createRun(page, `authoring-interruption-${Date.now()}`);
  await page.goto(`/p/${runId}/write`);
  const source = page.getByLabel('Fountain screenplay source');
  await expect(source).toBeVisible();
  const second = await context.newPage();
  await second.goto(`/p/${runId}/write`);
  await expect(second.locator('.phx-connected')).toBeVisible();
  await expect(second.getByLabel('Fountain screenplay source')).toBeVisible();
  await page.evaluate(() => window.addEventListener('phx:authoring:mark_saved', event => event.stopImmediatePropagation(), {once: true, capture: true}));
  const invalid = fixture + '\n[[unfinished';
  await source.fill(invalid);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Fountain needs attention');
  const beforeRetry = await page.locator('.workspace-header code').allTextContents();
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  expect(await page.locator('.workspace-header code').allTextContents()).toEqual(beforeRetry);
  await expect(page.locator('.authoring-status')).toContainText('Draft version 2');
  // No second history row/version appears when the acknowledgement is lost.
  await expect(page.locator('.draft-history li')).toHaveCount(1);
  await second.getByLabel('Fountain screenplay source').fill(fixture + '\nDifferent local text.');
  await second.getByRole('button', {name: 'Save working draft'}).click();
  await expect(second.getByRole('heading', {name: 'This draft changed in another tab'})).toBeVisible();
  await second.getByRole('button', {name: 'Use the newer saved draft'}).click();
  await expect(second.getByLabel('Fountain screenplay source')).toHaveValue(invalid);
  await expect(second.getByText(/last valid draft/)).toBeVisible();
  await second.reload();
  await expect(second.getByLabel('Fountain screenplay source')).toHaveValue(invalid);
  await expect(second.locator('[data-authoring-preview]')).toContainText('I can revise this.');
  await context.close();
});

test('E05/E06 immediate unsaved AI and acceptance clicks cannot race preview debounce', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `authoring-action-race-${Date.now()}`);
  await page.goto(`/p/${runId}/write`);
  await page.locator('#source-editor').fill(fixture+'\nA changed beat.');
  await page.getByRole('button',{name:'Save working draft'}).click();
  await page.getByRole('button', {name: 'Save proposed change'}).click();
  await expect(page.getByText(/The current screenplay is unchanged/)).toBeVisible();
  await page.evaluate(() => {
    const source = document.querySelector('[data-authoring-source]');
    source.value += '\nUnsaved immediate action.';
    source.dispatchEvent(new Event('input', {bubbles: true}));
    document.getElementById('candidate-accept').click();
  });
  await expect(page).toHaveURL(new RegExp(`/p/${runId}/write$`));
  await expect(page.getByText(/Unsaved text cannot be accepted/)).toBeVisible();
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  await page.getByRole('button', {name: 'Save proposed change'}).click();
  await expect(page.locator('.authoring-status')).toContainText('Proposed change saved');
  await page.goto(`/p/${runId}`);
  await expect(page.locator('.screenplay')).not.toContainText('Unsaved immediate action.');
});

import {test, expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {importProject, projectRunCount, seedTask, hostFixture} from './workspace_helpers.mjs';

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
  expect(await page.locator('[id]').evaluateAll(nodes => {const ids=nodes.map(n=>n.id);return ids.filter((id,index)=>ids.indexOf(id)!==index);})).toEqual([]);
  await page.setViewportSize({width:1440,height:400});
  const papers = page.locator('.source-comparison__paper');
  await papers.first().evaluate(el => {el.scrollTop=80;el.dispatchEvent(new Event('scroll'));});
  await expect.poll(() => papers.nth(1).evaluate(el=>el.scrollTop)).toBeGreaterThan(0);
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
  await expect(page.locator('.phx-connected')).toBeVisible();
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
  await expect(page.getByRole('heading', {name: 'Keep the withheld fact', exact: true})).toBeVisible();

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
  await page.getByLabel('To', {exact: true}).fill('Writer');
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
  await expect(page.getByRole('heading', {name: 'Cast', exact: true})).toBeVisible();
  await expect(page.locator('.character-grid')).toContainText('literal dialogue blocks');
  await expect(page.locator('.character-grid')).toContainText('unreviewed');
  const firstIdentity = page.locator('.compact-character-card').first();
  await firstIdentity.getByRole('button', {name: 'Confirm person'}).click();
  await expect(firstIdentity).toContainText('confirmed');
  await page.goto(`/p/${key}/locations`);
  await expect(page.getByRole('heading', {name: 'Locations', exact: true})).toBeVisible();
  await expect(page.locator('.location-workspace')).toContainText('KITCHEN');

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
  await page.getByLabel('Reader', {exact: true}).fill('Nora reader');
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
  await expect(page.locator('pre.script').nth(1)).toContainText('If you missed it, you were meant to.', {timeout: 60_000});

  await expect.poll(() => hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); [run] = FountWeb.Store.list_project_runs(Fount.Repo, owner, project["id"]); IO.puts("STATUS=" <> run["status"])', {FOUNT_FIXTURE_KEY:key}).split('STATUS=').at(-1).trim()).toMatch(/partial|completed_/);
  await page.goto(`/p/${key}/exports/task-1`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  await expect(page.getByRole('status')).toContainText('Delivery bundle published.');
  await page.goto(`/p/${key}/feedback`);
  await expect(page.locator('.phx-connected')).toBeVisible();
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
  await expect(page.getByRole('status')).toContainText('Human feedback saved.');
  await expect(page.getByRole('heading', {name: 'Saved responses'})).toBeVisible();
  await expect(page.locator('.feedback-report')).toContainText(/No combined quality, learning or preference score/);
  await page.reload();
  await expect(page.locator('.phx-connected')).toBeVisible();
  const reopened = page.locator('.feedback-form').first();
  await expect(reopened.getByLabel('Useful', {exact: true})).toBeChecked();
  await expect(reopened.getByLabel('I kept my original')).toBeChecked();
  await expect(reopened.getByLabel('Notes')).toHaveValue('Useful for comparison, but I kept the original.');
  await expect(reopened.getByRole('button', {name: 'Update optional feedback'})).toBeVisible();
  await reopened.getByLabel('Mixed', {exact:true}).check();
  await reopened.locator('details > summary', {hasText:'More detail'}).click();
  await reopened.getByLabel('Task completion').fill('');
  const clearVoice = reopened.locator('input[name="feedback[dimensions][voice_retention]"][value=""]');
  if (await clearVoice.count()) await clearVoice.check();
  await reopened.getByRole('button',{name:'Update optional feedback'}).click();
  await expect(page.getByRole('status')).toContainText('Human feedback saved.');
  await page.reload();
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.locator('.feedback-form').first().getByLabel('Mixed',{exact:true})).toBeChecked();
  const recordFacts = hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); rows = FountWeb.ProductionStore.list_usefulness(Fount.Repo, owner, project["id"]); IO.puts("FEEDBACK=" <> Jason.encode!(Enum.map(rows, & &1["record"]["human_response"])))', {FOUNT_FIXTURE_KEY:key});
  expect(recordFacts.split('FEEDBACK=').at(-1).trim()).not.toContain('task_completion');
  expect(JSON.parse(recordFacts.split('FEEDBACK=').at(-1).trim())).toHaveLength(1);
  await capture(page, 'ux03-feedback-independent-dimensions');
});

test('UX03 exact Fountain, FDX and PDF exports preview/download from the named current revision', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-exports', source);
  await page.goto(`/p/${key}/exports`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Exports'})).toBeVisible();

  await page.getByRole('button', {name: 'Build Fountain'}).click();
  await expect(page.locator('.artifact-row').first()).toContainText('.fountain');
  const fountainPreview = await page.getByRole('link', {name: 'Preview'}).first().getAttribute('href');
  await page.goto(fountainPreview);
  await expect(page.locator('body')).toContainText('coffee maker');

  await page.goto(`/p/${key}/exports`);
  await expect(page.locator('.phx-connected')).toBeVisible();
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
  await page.goto(`/p/${key}`);
  await expect(page.getByRole('navigation',{name:'Page layout'}).getByRole('link',{name:'Exported pages',exact:true})).toBeVisible();
  await expect(page.getByRole('link',{name:'Build exported pages',exact:true})).toHaveCount(0);
  await page.getByRole('navigation',{name:'Page layout'}).getByRole('link',{name:'Exported pages',exact:true}).click();
  await expect(page.getByTitle(/exported PDF page 1/)).toBeVisible();
});

function sourceMutation(key, operation) {
  hostFixture(`owner = System.fetch_env!("FOUNT_OWNER_ID"); key = System.fetch_env!("FOUNT_FIXTURE_KEY"); {:ok, model} = Fount.Persistence.load(Fount.Repo, key); node = Enum.find(model.ir.elements, &(&1.type == :action and String.contains?(&1.text || "", "coffee maker"))); op = if System.fetch_env!("FOUNT_FIXTURE_OPERATION") == "delete", do: %{"kind" => "delete_elements", "value" => %{"ids" => [node.id]}}, else: Fount.Edit.replace_text(node.id, "MARA moves the coffee maker to the window."); {:ok, changed, _} = Fount.Screenplay.apply(model, [op], actor: "writer:" <> owner); {:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, key, changed, expected_revision: model.revision.id, operations: [op]); {:ok, stored} = Fount.Persistence.candidate(Fount.Repo, candidate.id); {:ok, principal} = Fount.Writing.Principal.new(:human, owner); {:ok, authority} = Fount.Writing.Authority.new(principal, model.id, [:approve]); {:ok, approval} = Fount.Writing.Approval.direct(stored, principal, Fount.ID.v4()); {:ok, _} = Fount.Persistence.accept_candidate(Fount.Repo, candidate.id, approval: approval, authority: authority)`, {FOUNT_FIXTURE_KEY:key, FOUNT_FIXTURE_OPERATION:operation});
}

test('UX03 note categories, literal filtering, reviewer conflicts, changed/deleted targets and named remapping complete the reader loop', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const key = await importProject(first, 'ux03-note-loop', source);
  await first.goto(`/p/${key}/notes`);
  await expect(first.locator('.phx-connected')).toBeVisible();
  const form = first.locator('form[phx-submit="save_note"]').first();
  const target = form.locator('select[name="note[target]"]');
  const value = await target.locator('option', {hasText:'coffee maker'}).first().getAttribute('value');
  await target.selectOption(value);
  await form.getByLabel('Title', {exact:true}).fill('Literal [coffee] note');
  await form.getByLabel('Note', {exact:true}).fill('Keep the pause literal [coffee].');
  const category = form.locator('select[name="note[category]"]');
  const categoryValue = await category.locator('option').nth(1).getAttribute('value');
  await category.selectOption(categoryValue);
  await first.getByRole('button',{name:'Save proposed note'}).click();
  await first.getByRole('button',{name:'Make this note change current'}).click();
  const filters = first.locator('.note-filters');
  await filters.locator('input[name="notes[query]"]').fill('[coffee]');
  await filters.locator('select[name="notes[category]"]').selectOption(categoryValue);
  await filters.getByRole('button').click();
  await expect(first.locator('.note-card')).toHaveCount(1);
  await filters.locator('input[name="notes[query]"]').fill('nomatch');
  await filters.getByRole('button').click();
  await expect(first.locator('.note-card')).toHaveCount(0);
  await first.reload();
  const second = await context.newPage();
  await second.goto(`/p/${key}/notes`);
  await expect(second.locator('.phx-connected')).toBeVisible();
  const a = first.locator('.note-review-response');
  const b = second.locator('.note-review-response');
  await a.getByLabel('Response').selectOption('addressed');
  await a.getByLabel('Comment').fill('First reviewer saved.');
  await a.getByRole('button').click();
  await b.getByLabel('Response').selectOption('deferred');
  await b.getByLabel('Comment').fill('Recover this attempted reviewer text.');
  await b.getByRole('button').click();
  await expect(second.locator('.note-review-conflict')).toBeVisible();
  await expect(b.getByLabel('Comment')).toHaveValue('Recover this attempted reviewer text.');
  await b.getByRole('button').click();
  await expect(b.locator('input[name="review[version]"]')).toHaveValue('2');
  await expect(second.locator('.note-review-conflict')).toHaveCount(0);
  await b.getByLabel('Response').selectOption('not_addressed');
  await b.getByRole('button').click();
  await expect(b.locator('input[name="review[version]"]')).toHaveValue('3');
  await b.getByLabel('Response').selectOption('open');
  await b.getByRole('button').click();
  await expect(b.locator('input[name="review[version]"]')).toHaveValue('0');
  const reviewCount = hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); IO.puts("REVIEWS=" <> Integer.to_string(length(FountWeb.ProductionTools.note_reviews(Fount.Repo, owner, project["id"]))))', {FOUNT_FIXTURE_KEY:key});
  expect(reviewCount).toContain('REVIEWS=0');
  sourceMutation(key, 'change');
  await first.reload();
  await expect(first.locator('.note-card')).toContainText('The passage changed');
  sourceMutation(key, 'delete');
  await first.reload();
  await expect(first.locator('.note-card')).toContainText(/not available|deleted|no longer/i);
  await first.getByLabel('Exact literal search').fill('The train is late');
  await first.getByRole('button',{name:'Find passages'}).click();
  await first.locator('.note-edit-panel > summary').click();
  const remap = first.locator('select[name="note[target_override]"]');
  await remap.selectOption(await remap.locator('option').nth(1).getAttribute('value'));
  await first.getByRole('button',{name:'Save proposed change', exact:true}).click();
  await first.getByRole('button',{name:'Make this note change current'}).click();
  await expect(first.locator('.note-card .source-excerpt')).toContainText('The train is late');
  await capture(first, 'ux03-note-remap-recovered');
  expect(projectRunCount(key)).toBe(0);
  await context.close();
});

test('UX03 artifact failures return to exact-source Exports and dated PDF checks stay mechanical', async ({page}) => {
  await login(page);
  const key = await importProject(page, 'ux03-artifact-errors', source);
  hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); key = System.fetch_env!("FOUNT_FIXTURE_KEY"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, key); {:ok, model} = Fount.Persistence.load(Fount.Repo, key); {:error, _} = FountWeb.ReadingArtifacts.build_source(Fount.Repo, owner, project, model, "pdf", pdf_options: [renderer: "/nonexistent/ux03-renderer"])', {FOUNT_FIXTURE_KEY:key});
  await page.goto(`/p/${key}/exports`);
  await expect(page.locator('.artifact-list')).toContainText('renderer is not installed');
  await page.getByRole('button',{name:'Build PDF'}).click();
  await expect(page.getByRole('link',{name:'Read numbered PDF pages'})).toBeVisible();
  await page.locator('select[name="submission[target]"]').selectOption('nicholl_2026_27');
  await page.locator('form[phx-submit="check_submission"] button').click();
  await expect(page.locator('main')).toContainText('2026-09-23');
  await expect(page.locator('main')).toContainText(/mechanical/i);
  await capture(page,'ux03-dated-mechanical-checks');
  const pdfHref = await page.getByRole('link',{name:'Read numbered PDF pages'}).getAttribute('href');
  await page.getByRole('button',{name:'Build Fountain'}).click();
  const href = await page.getByRole('link',{name:'Download', exact:true}).first().getAttribute('href');
  hostFixture('owner = System.fetch_env!("FOUNT_OWNER_ID"); {:ok, project} = FountWeb.Store.project_by_key(Fount.Repo, owner, System.fetch_env!("FOUNT_FIXTURE_KEY")); {:ok, row} = FountWeb.ProductionStore.project_artifact_by_ref(Fount.Repo, owner, project["id"], System.fetch_env!("FOUNT_FIXTURE_REF")); :ok = File.rm(Path.join(Application.fetch_env!(:fount_web, :artifact_root), row["output_location"]))', {FOUNT_FIXTURE_KEY:key, FOUNT_FIXTURE_REF:href.split("/").at(-2)});
  await page.goto(href);
  await expect(page).toHaveURL(new RegExp(`/p/${key}/exports`));
  await expect(page.getByRole('alert')).toContainText('Build it again');
  await page.getByRole('button',{name:'Build Fountain'}).click();
  await expect(page.locator('.artifact-row').first()).toContainText('ready');
  sourceMutation(key, 'change');
  await page.goto(pdfHref);
  await expect(page.locator('main')).toContainText('Earlier saved draft');
  await expect(page.getByRole('heading',{name:'Exported pages'})).toBeVisible();
  await capture(page,'ux03-earlier-exact-pdf');
  expect(projectRunCount(key)).toBe(0);
});

test('UX03 saved table-read timing, finite speeds, reaction conflicts, reconnect and immutable export identity remain recoverable', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const longSource = source + Array.from({length:30}, (_,i) => `\n\nMARA\nReader turn ${i+1}: a long human pause keeps the scene in the room until the next answer.`).join('');
  const key = await importProject(first, 'ux03-timing-conflict', longSource);
  await first.goto(`/p/${key}/read`);
  await first.getByLabel('Read title').fill('Named human timing read');
  await first.getByRole('button',{name:'Save table-read material'}).click();
  const workspace = first.locator('#table-read-workspace');
  await expect(workspace).toBeVisible();
  const speed = first.locator('[data-read-speed]');
  expect(await speed.locator('option').evaluateAll(options=>options.map(o=>o.value))).toEqual(['0.5','1','1.5','2']);
  await speed.selectOption('2');
  await first.getByRole('button',{name:'Start / pause'}).click();
  await expect(workspace).toHaveAttribute('data-scroll-mode','auto');
  await expect(first.locator('[data-read-elapsed]')).not.toHaveText('00:00');
  await first.getByRole('button',{name:'Start / pause'}).click();
  await expect(workspace).toHaveAttribute('data-scroll-mode','paused');
  expect(Number(await workspace.getAttribute('data-elapsed-ms'))).toBeGreaterThan(500);
  await first.getByRole('button',{name:'Start / pause'}).click();
  await expect(workspace).toHaveAttribute('data-scroll-mode','auto');
  await first.getByRole('button',{name:'Start / pause'}).click();
  await expect(workspace).toHaveAttribute('data-scroll-mode','paused');
  const exportHref = await first.getByRole('link',{name:'Export saved table-read JSON'}).getAttribute('href');
  const second = await context.newPage();
  await second.goto(`/p/${key}/read`);
  await second.locator('.saved-read-row').click();
  await first.getByRole('button',{name:'Bookmark current passage'}).click();
  await expect(workspace).toHaveAttribute('data-scroll-mode','manual');
  await second.getByLabel('Reader',{exact:true}).fill('Second reader');
  await second.locator('textarea[name="reaction[reaction]"]').fill('Recover the human reaction verbatim.');
  await second.getByRole('button',{name:'Save reaction'}).click();
  await expect(second.locator('.reaction-conflict')).toBeVisible();
  await expect(second.locator('textarea[name="reaction[reaction]"]')).toHaveValue('Recover the human reaction verbatim.');
  await second.getByRole('button',{name:'Save reaction'}).click();
  await expect(second.locator('.reaction-list')).toContainText('Recover the human reaction verbatim.');
  await context.setOffline(true);
  await second.evaluate(() => window.liveSocket.disconnect());
  await expect.poll(() => second.evaluate(() => window.liveSocket.isConnected())).toBe(false);
  await context.setOffline(false);
  await second.evaluate(() => window.liveSocket.connect());
  await expect.poll(() => second.evaluate(() => window.liveSocket.isConnected())).toBe(true);
  await expect(second.locator('.phx-connected')).toBeVisible();
  await second.locator('.saved-read-row').click();
  await expect(second.locator('.reaction-list')).toContainText('Recover the human reaction verbatim.');
  await second.getByLabel('Read title').fill('Another human read');
  await second.getByRole('button',{name:'Save table-read material'}).click();
  await expect(second.locator('.saved-read-row')).toHaveCount(2);
  const packet = await second.request.get(exportHref);
  expect(packet.ok()).toBe(true);
  expect((await packet.json()).packet.display_title).toBe('Named human timing read');
  await capture(second,'ux03-table-read-reaction-reconnect');
  expect(projectRunCount(key)).toBe(0);
  await context.close();
});

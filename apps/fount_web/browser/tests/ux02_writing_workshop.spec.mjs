import {openWritingMenu} from './workspace_helpers.mjs';
import {test, expect} from '@playwright/test';
import {importProject, projectRunCount} from './workspace_helpers.mjs';

import {readFileSync} from 'node:fs';

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
  await editor.press('Control+End');
  await editor.pressSequentially('\nA quiet mechanical hum.');
  await page.keyboard.press('Escape');
  await expect(page.locator('#project-editor')).not.toHaveClass(/is-focus-mode/);
  await expect(editor).toHaveValue(before + '\nA quiet mechanical hum.');

  await openWritingMenu(page, 'More');
  await expect(page.getByRole('button', {name: 'Typewriter scroll off'})).toBeVisible();
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText(/Saved working draft/i);

  await page.locator('#scene-cards > summary').click();
  const firstCard = page.locator('[data-scene-card]').first();
  await firstCard.focus();
  await page.keyboard.press('Alt+ArrowDown');
  await expect(page.locator('[data-scene-card]').first()).toContainText('INT. SERVICE ELEVATOR - NIGHT');
  await page.reload();
  await expect(editor).toHaveValue(/A quiet mechanical hum/);
  await page.locator('#scene-cards > summary').click();
  await expect(page.locator('[data-scene-card]').first()).toContainText('INT. SERVICE ELEVATOR - NIGHT');
  await capture(page, 'ux02-writing-scene-cards');
  expect(projectRunCount(key)).toBe(0);
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
  await page.locator('.preset-card', {hasText: 'UX02 careful'}).first().getByRole('button', {name: 'Export JSON'}).click();
  const download = await downloadPromise;
  const exported=JSON.parse(readFileSync(await download.path(),'utf8'));
  expect(JSON.stringify(exported)).toContain('12500000');
  await page.getByLabel('Maximum spend').fill('1.00');
  await page.getByRole('button',{name:'Save task settings'}).click();
  await expect(page.getByText(/Task settings saved/)).toBeVisible();
  await page.locator('.preset-card',{hasText:'UX02 careful'}).first().getByRole('button',{name:'Apply settings'}).click();
  await page.reload();
  await expect(page.getByLabel('Maximum spend')).toHaveValue('12.5');
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
  expect(projectRunCount(key)).toBe(0);
  const returnHref=await page.getByRole('link',{name:'Return to passage'}).first().getAttribute('href');
  await page.getByRole('button',{name:'Start line alternatives'}).click();
  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button',{name:'Commit now',exact:true}).click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.',{timeout:60000});
  await expect(page.locator('pre.script').nth(1)).toContainText('He said eleven.');
  await expect(page.locator('pre.script').nth(1)).toContainText('MARA watches the elevator numbers.');
  await page.goto(returnHref);
  await expect(page.locator('.screenplay')).toBeVisible();
  const anchor=new URL(page.url()).hash.slice(1);
  await expect(page.locator(`[id="${anchor}"]`)).toBeVisible();


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
  await expect(page.getByText('Proposed note changes', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Make this note change current'}).click();
  await expect(page.getByRole('heading', {name: 'Keep the withheld fact', exact: true})).toBeVisible();

  await page.getByRole('button', {name: 'Work on this note now'}).click();
  await expect(page.getByText('Related work', {exact: true})).toBeVisible();
  await page.getByRole('button', {name: 'Start this work'}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-[0-9]+/setup$`));

  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button',{name:'Commit now',exact:true}).click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.',{timeout:60000});
  await page.goto(`/p/${key}/notes`);
  await expect(page.getByRole('link',{name:'Open linked proposal'})).toBeVisible();
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

test('UX02 selected alternatives preserve exact protections and save auditioned selections without accepting pages', async ({page}) => {
  await login(page);
  const key=await importProject(page,'ux02-selected-approaches',source);
  await page.goto(`/p/${key}/work`); await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.locator('#creative-scope-picker')).not.toHaveAttribute('open','');
  await expect(page.locator('#creative-protection-picker')).not.toHaveAttribute('open','');
  await capture(page,'ux02-short-default-work');
  await page.getByLabel('What do you want to change or understand?').fill('Explore two different ways for Mara to hold the silence.');
  await page.locator('#creative-scope-picker > summary').click();
  await page.locator('#creative-scope label',{hasText:'Scene 1 · INT. HALLWAY - NIGHT'}).locator('input').check();
  await expect(page.locator('input[name="task[scope][]"][value="whole"]')).not.toBeChecked();
  await page.locator('#creative-protection-picker > summary').click();
  await page.locator('#creative-protections label',{hasText:'He said eleven.'}).locator('input').check();
  await page.locator('input[name="task[action]"][value="alternatives"]').first().check();
  await page.locator('.task-details > summary').click();
  await page.locator('input[name="task[alternatives]"]').fill('2');
  await page.locator('textarea[name="task[approaches]"]').fill('Quiet restraint\nA pointed delay');
  await page.getByRole('button',{name:'Review brief'}).click();
  await expect(page.locator('.creative-review')).toContainText('MARA watches the elevator numbers.');
  await expect(page.locator('.creative-review')).toContainText('He said eleven.');
  await capture(page,'ux02-selected-protected-brief');
  await page.getByRole('button',{name:'Start this work'}).click();
  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  const approach=page.getByRole('button',{name:'Commit now',exact:true});
  await expect(approach).toBeVisible({timeout:60000});
  await expect(page.getByRole('button',{name:'Delay',exact:true})).toBeVisible();
  await approach.click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('.related-candidate').first()).toBeVisible({timeout:60000});
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.');
  await expect(page.locator('pre.script').nth(1)).toContainText('He said eleven.');
  await page.locator('.related-candidate').first().getByRole('button',{name:'Audition in context'}).click();
  await expect(page.getByRole('region',{name:'Candidate audition'})).toContainText('He said eleven.');
  const originalCount=await page.locator('.related-candidate').count();
  const selected=page.locator('.related-candidate').first();
  await selected.locator('input[name="candidate[groups][]"]').first().check();
  await selected.getByRole('button',{name:'Save selected changes as related proposal'}).click();
  await expect(page.locator('.related-candidate')).toHaveCount(originalCount+1);
  const sources=page.locator('.candidate-combine-source');
  await sources.first().locator('input[type=checkbox]').first().check();
  await sources.last().locator('input[type=checkbox]').nth(1).check();
  await page.getByRole('button',{name:'Save recombined proposal'}).click();
  await expect(page.locator('.related-candidate')).toHaveCount(originalCount+2);
  await page.setViewportSize({width:390,height:844}); await capture(page,'ux02-phone-proposal-review');
  await page.goto(`/p/${key}`);
  await expect(page.locator('.screenplay')).not.toContainText('The silence holds.');
});

test('UX02 Focus preserves unsaved text when another tab saves and reports a real conflict', async ({browser}) => {
  const context=await browser.newContext(); const page=await context.newPage(); await login(page);
  const key=await importProject(page,'ux02-focus-conflict',source);
  await page.goto(`/p/${key}/write`); await expect(page.locator('.phx-connected')).toBeVisible();
  const second=await context.newPage(); await second.goto(`/p/${key}/write`); await expect(second.locator('.phx-connected')).toBeVisible();
  await page.getByRole('button',{name:'Focus',exact:true}).click();
  const editor=page.locator('#source-editor'); const initial=await editor.inputValue();
  await second.locator('#source-editor').fill(initial+'\nServer tab text.');
  await second.getByRole('button',{name:'Save working draft'}).click();
  await expect(second.locator('.authoring-status')).toContainText('Saved working draft');
  await editor.fill(initial+'\nUnsaved Focus text.');
  await editor.press('Control+s');
  await expect(page.getByRole('heading', {name:'This draft changed in another tab'})).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(editor).toHaveValue(initial+'\nUnsaved Focus text.');
  await capture(page,'ux02-focus-conflict-preserved');
  await context.close();
});

test('UX02 manual proposal adjustment is rechecked and exact reviewed writing becomes current only after approval', async ({page}) => {
  await login(page); const key=await importProject(page,'ux02-manual-review',source);
  await page.goto(`/p/${key}/work`); await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByLabel('What do you want to change or understand?').fill('Let the hesitation remain visible in the hallway.');
  await page.getByRole('button',{name:'Review brief'}).click();
  await page.getByRole('button',{name:'Start this work'}).click();
  await page.locator('.preset-card',{hasText:'Owner approval'}).getByRole('button',{name:'Apply settings'}).click();
  await expect(page.locator('select[name="policy[completion]"]')).toHaveValue('accept');
  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button',{name:'Commit now',exact:true}).click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.',{timeout:60000});
  const proposal=await page.locator('pre.script').nth(1).innerText();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByLabel('Replacement Fountain').fill(proposal.replace('The silence holds.','A measured silence.'));
  await page.getByRole('button',{name:'Save manual adjustment and re-check'}).click();
  await expect(page.getByRole('status')).toContainText('Decision recorded');
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').nth(1)).toContainText('A measured silence.',{timeout:60000});
  await page.goto(`/p/${key}`); await expect(page.locator('.screenplay')).not.toContainText('A measured silence.');
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button',{name:'Make this exact checked proposal current'}).click();
  await expect(page.getByRole('status')).toContainText('Decision recorded');
  await page.goto(`/p/${key}`); await expect(page.locator('.screenplay')).toContainText('A measured silence.',{timeout:60000});
  await capture(page,'ux02-reviewed-proposal-current');
});

test('UX02 a source change requires a real rebase before exact proposal approval', async ({page}) => {
  await login(page); const key=await importProject(page,'ux02-rebase-review',source);
  await page.goto(`/p/${key}/work`); await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByLabel('What do you want to change or understand?').fill('Let the first hallway beat hesitate.');
  await page.getByRole('button',{name:'Review brief'}).click(); await page.getByRole('button',{name:'Start this work'}).click();
  await page.locator('.preset-card',{hasText:'Owner approval'}).getByRole('button',{name:'Apply settings'}).click();
  await expect(page.locator('select[name="policy[completion]"]')).toHaveValue('accept');
  await page.getByRole('button',{name:'Start / resume task'}).click();
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await expect(page.getByRole('button',{name:'Commit now',exact:true})).toBeVisible({timeout:60000});
  const writing=await page.context().newPage(); await writing.goto(`/p/${key}/write`); await expect(writing.locator('.phx-connected')).toBeVisible();
  const editor=writing.locator('#source-editor'); const original=await editor.inputValue();
  await editor.fill(original+'\nA distant engine turns over.');
  await writing.getByRole('button',{name:'Save working draft'}).click();
  await openWritingMenu(writing, 'Changes');
  await writing.getByRole('button',{name:'Save proposed change'}).click();
  await openWritingMenu(writing, 'Changes');
  await writing.getByRole('button',{name:'Make proposed change current'}).click();
  await expect(writing.getByText(/Revision approved and saved/)).toBeVisible(); await writing.close();
  await page.getByRole('button',{name:'Commit now',exact:true}).click();
  const rebase=page.getByRole('button',{name:'Rebase onto the current screenplay'});
  await expect(rebase).toBeVisible({timeout:60000});
  await expect(page.getByRole('button',{name:'Make this exact checked proposal current'})).toHaveCount(0);
  await capture(page,'ux02-stale-source-rebase-required');
  await rebase.click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-2/decisions`));
  await expect(page.getByRole('button',{name:'Make this exact checked proposal current'})).toBeVisible({timeout:60000});
  await page.goto(`/p/${key}/changes/task-2`);
  await expect(page.locator('pre.script').nth(1)).toContainText('A distant engine turns over.');
  await expect(page.locator('pre.script').nth(1)).toContainText('The silence holds.');
  await page.goto(`/p/${key}/activity/task-2/decisions`);
  await page.getByRole('button',{name:'Make this exact checked proposal current'}).click();
  await expect(page.getByRole('status')).toContainText('Decision recorded');
  await page.goto(`/p/${key}`); await expect(page.locator('.screenplay')).toContainText('The silence holds.',{timeout:60000});
  await expect(page.locator('.screenplay')).toContainText('A distant engine turns over.');
});

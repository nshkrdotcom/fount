import {test, expect} from '@playwright/test';
import {openWorkspace, projectRunCount, workspaceReady} from './workspace_helpers.mjs';

const token=process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const source=`Title: SI02 BROWSER\n\nINT. MERCY HOSPITAL - RECORDS WINDOW - LATE NIGHT (2031)\n\n!WORK ORDER\nAUTHORIZED STAFF ONLY\n\nDR. MIRA VALE (O.S.)\nBring me the chart.\n\nMIRA VALE\nThank you.\n\nGUARD\nWest door.\n\nGUARD\nEast door.\n\nEVELYN enters carrying a sealed envelope.\n`;

async function login(page){
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button',{name:'Sign in'}).click();
  await workspaceReady(page);
}

async function importWithAssessment(page,name){
  await openWorkspace(page,'/new');
  await page.locator('input[type=file]').setInputFiles({name:`${name}.fountain`,mimeType:'text/plain',buffer:Buffer.from(source)});
  await page.getByRole('button',{name:'Preview import'}).click();
  await expect(page.getByRole('heading',{name:`${name}.fountain`})).toBeVisible();
  const consent=page.getByLabel('Assess cast & locations after import');
  await expect(consent).toBeVisible();
  await expect(page.locator('.semantic-import-consent')).toContainText('gpt-6.1-sol');
  await expect(page.locator('.semantic-import-consent')).toContainText('low reasoning');
  await consent.check();
  await page.getByRole('button',{name:'Open screenplay'}).click();
  await expect(page).toHaveURL(/\/p\/[^/]+$/);
  await workspaceReady(page);
  return new URL(page.url()).pathname.split('/')[2];
}

test('SI02 consent launches exactly one durable assessment and keeps printed words out of Cast', async ({page,context})=>{
  test.skip(process.env.FOUNT_SEMANTIC_ASSESSMENT_MODE!=='deterministic_fixture','run the focused SI02 browser gate with deterministic_fixture mode');
  await login(page);
  const key=await importWithAssessment(page,`si02-${Date.now()}`);
  expect(projectRunCount(key)).toBe(1);

  await openWorkspace(page,`/p/${key}/cast`);
  await expect(page.locator('#semantic-assessment-status')).toContainText('Suggestions ready',{timeout:20_000});
  await expect(page.locator('#semantic-assessment-status')).toContainText('gpt-6.1-sol');
  await expect(page.locator('.character-grid')).not.toContainText('WORK ORDER');
  await expect(page.locator('.character-grid').getByRole('heading',{name:'GUARD',exact:true})).toHaveCount(2);
  await expect(page.locator('.character-grid')).toContainText('EVELYN');
  await expect(page.locator('.character-grid')).toContainText('suggested');
  await expect(page.locator('.character-grid')).toContainText('DR. MIRA VALE');

  const response=await context.request.get(`/p/${key}/source-review/export.json`);
  expect(response.ok()).toBeTruthy();
  const exported=await response.json();
  expect(exported.assessment.model).toBe('gpt-6.1-sol');
  expect(exported.assessment.reasoning_effort).toBe('low');
  expect(exported.assessment.run_id).toBeTruthy();
  expect(exported.provenance.screenplay_accepted_by_review).toBe(false);

  const mira=page.locator('.compact-character-card').filter({hasText:'MIRA VALE'}).first();
  await mira.getByRole('button',{name:'Confirm person'}).click();
  await expect(mira).toContainText('confirmed');
  expect(projectRunCount(key)).toBe(1);
});

test('SI02 reassessment is explicit history and never accepts screenplay changes', async ({page,context})=>{
  test.skip(process.env.FOUNT_SEMANTIC_ASSESSMENT_MODE!=='deterministic_fixture','run the focused SI02 browser gate with deterministic_fixture mode');
  await login(page);
  const key=await importWithAssessment(page,`si02-history-${Date.now()}`);
  await openWorkspace(page,`/p/${key}/cast`);
  await expect(page.locator('#semantic-assessment-status')).toContainText('Suggestions ready',{timeout:20_000});

  const before=await (await context.request.get(`/p/${key}/source-review/export.json`)).json();
  await page.getByRole('button',{name:'Reassess this draft'}).click();
  await expect(page.locator('#semantic-assessment-status')).toContainText('Suggestions ready',{timeout:20_000});
  expect(projectRunCount(key)).toBe(2);
  await expect(page.locator('#semantic-assessment-status')).toContainText('Assessment history');

  const after=await (await context.request.get(`/p/${key}/source-review/export.json`)).json();
  expect(after.source.revision_id).toBe(before.source.revision_id);
  expect(after.source.source_sha256).toBe(before.source.source_sha256);
  await expect.poll(async () => {
    const current = await (await context.request.get(`/p/${key}/source-review/export.json`)).json();
    return current.assessment.id;
  }).not.toBe(before.assessment.id);
  const completed = await (await context.request.get(`/p/${key}/source-review/export.json`)).json();
  expect(completed.assessment.id).not.toBe(before.assessment.id);
  expect(after.provenance.screenplay_accepted_by_review).toBe(false);
});

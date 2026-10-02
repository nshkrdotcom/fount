import {test, expect} from '@playwright/test';
import {importProject, projectRunCount} from './workspace_helpers.mjs';

const token=process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const source=`Title: SOURCE IDENTITIES\n\nINT. NORTH STATION - PLATFORM - NIGHT(2030)\n\n!AUTHORIZED PERSONNEL ONLY\n!STICKY NOTE: KEEP OUT\n!WORK ORDER 17-B\nDO NOT ENTER.\n\nGUARD\nStop.\n\nALEX crosses the empty concourse without speaking.\n\nINT. NORTH STATION - PLATFORM - LATE AFTERNOON\n\nGUARD (O.S.)\nAgain.\n\nYOUNG MARA\nWait.\n\nMARA (O.S.)\nNot yet.\n`;

async function login(page){
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button',{name:'Sign in'}).click();
  await expect(page.locator('.phx-connected')).toBeVisible();
}

test('SI01 import keeps source cues unreviewed, manual review creates zero Runs, and Cast/Locations are separate', async ({page})=>{
  await login(page);
  const key=await importProject(page,`si01-${Date.now()}`,source);
  expect(projectRunCount(key)).toBe(0);

  await page.goto(`/p/${key}/cast`);
  await expect(page.getByRole('heading',{name:'Cast',exact:true})).toBeVisible();
  await expect(page.locator('#semantic-assessment-status')).toContainText('Not configured');
  await expect(page.locator('#semantic-assessment-status')).toContainText('SI02');
  await expect(page.locator('.character-grid')).toContainText('GUARD');
  await expect(page.locator('.character-grid')).not.toContainText('AUTHORIZED PERSONNEL ONLY');
  await expect(page.locator('.character-grid')).not.toContainText('STICKY NOTE: KEEP OUT');
  await expect(page.locator('.character-grid')).not.toContainText('WORK ORDER 17-B');
  await expect(page.locator('.character-grid')).not.toContainText('ALEX');
  await expect(page.locator('.character-grid')).toContainText('YOUNG MARA');
  await expect(page.locator('.character-grid')).toContainText('MARA');
  await expect(page.locator('.character-grid')).toContainText('unreviewed');

  const first=page.locator('.compact-character-card').first();
  await first.getByRole('button',{name:'Confirm person'}).click();
  await expect(first).toContainText('confirmed');
  expect(projectRunCount(key)).toBe(0);

  await page.goto(`/p/${key}/locations`);
  await expect(page.getByRole('heading',{name:'Locations',exact:true})).toBeVisible();
  await expect(page.locator('.location-workspace')).toContainText('NORTH STATION - PLATFORM');
  await expect(page.locator('.location-workspace')).toContainText('2030');
  await expect(page.locator('.location-workspace')).toContainText('LATE AFTERNOON');
  expect(projectRunCount(key)).toBe(0);
});


test('SI01 stale source review is recovered across two tabs without creating a Run', async ({browser})=>{
  const context=await browser.newContext();
  const firstPage=await context.newPage();
  const stalePage=await context.newPage();
  await login(firstPage);
  await login(stalePage);

  const key=await importProject(firstPage,`si01-conflict-${Date.now()}`,source);
  await firstPage.goto(`/p/${key}/cast`);
  await stalePage.goto(`/p/${key}/cast`);
  await expect(firstPage.locator('.compact-character-card').first()).toBeVisible();
  await expect(stalePage.locator('.compact-character-card').first()).toBeVisible();

  await firstPage.locator('.compact-character-card').first().getByRole('button',{name:'Confirm person'}).click();
  await expect(firstPage.locator('.compact-character-card').first()).toContainText('confirmed');

  await stalePage.locator('.compact-character-card').nth(1).getByRole('button',{name:'Reject as cast'}).click();
  await expect(stalePage.locator('main')).toContainText('Source review changed in another tab');
  await expect(stalePage.locator('.semantic-history')).toContainText('conflict');
  expect(projectRunCount(key)).toBe(0);

  await context.close();
});

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
  await expect(page.locator('.character-grid').getByRole('heading',{name:'GUARD',exact:true})).toHaveCount(2);
  await expect(page.locator('.character-grid')).toContainText('GUARD (O.S.)');
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

for (const viewport of [
  {width:1440,height:1000}, {width:1920,height:1080},
  {width:768,height:1024}, {width:1024,height:768}, {width:390,height:844}
]) {
  test(`SI01 Cast, Locations and Help retain review controls at ${viewport.width}px`, async ({browser}) => {
    const context=await browser.newContext({viewport,hasTouch:viewport.width===390,isMobile:viewport.width===390});
    const page=await context.newPage();
    await page.emulateMedia({reducedMotion:'reduce'});
    await login(page);
    const key=await importProject(page,`si01-layout-${viewport.width}-${Date.now()}`,source+'\nEXT. ROAD - LATER\n\nA cart rolls away.\n\nINT. HALL - UNKNOWABLE\n\nSilence.\n');
    for (const destination of ['cast','locations']) {
      await page.goto(`/p/${key}/${destination}`);
      await expect(page.locator('.phx-connected')).toBeVisible();
      const confirm=page.getByRole('button',{name:destination==='cast'?'Confirm person':'Confirm place'}).first();
      await confirm.focus();
      await page.keyboard.press('Enter');
      await expect(page.locator('.semantic-history')).toContainText('applied');
      expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBeLessThanOrEqual(2);
      const controls=await page.locator('.semantic-review-controls input:not([type=hidden]), .semantic-review-controls select, .semantic-review-controls button').evaluateAll(nodes=>nodes.filter(n=>n.getClientRects().length).map(n=>({left:n.getBoundingClientRect().left,right:n.getBoundingClientRect().right,width:innerWidth})));
      for (const control of controls) { expect(control.left).toBeGreaterThanOrEqual(0); expect(control.right).toBeLessThanOrEqual(control.width+2); }
      if (destination==='locations') {
        await expect(page.locator('.location-workspace')).toContainText('Place: NORTH STATION');
        await expect(page.locator('.location-workspace')).toContainText('Subplace: PLATFORM');
        await expect(page.locator('.location-workspace')).toContainText('Relative time: LATER');
        await expect(page.locator('.location-workspace')).toContainText('Unknown / unparsed');
      }
      if (process.env.FOUNT_ARTIFACT_ROOT) await page.screenshot({path:`${process.env.FOUNT_ARTIFACT_ROOT}/si01-${destination}-${viewport.width}.png`,fullPage:true});
    }
    await page.goto('/help#cast-locations');
    await expect(page.getByRole('heading',{name:'Cast & locations',exact:true})).toBeVisible();
    expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBeLessThanOrEqual(2);
    if (process.env.FOUNT_ARTIFACT_ROOT) await page.screenshot({path:`${process.env.FOUNT_ARTIFACT_ROOT}/si01-help-${viewport.width}.png`,fullPage:true});
    expect(projectRunCount(key)).toBe(0);
    await context.close();
  });
}

test('SI01 review exports exact provenance and promotion advances only through typed acceptance', async ({page,context}) => {
  await login(page);
  const key=await importProject(page,`si01-promotion-${Date.now()}`,source);
  const exported=async()=>{
    const response=await context.request.get(`/p/${key}/source-review/export.json`);
    expect(response.ok()).toBeTruthy();
    return response.json();
  };
  const before=await exported();
  await page.goto(`/p/${key}/cast`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  const first=page.locator('.compact-character-card').first();
  await first.getByRole('button',{name:'Confirm person'}).focus();
  await page.keyboard.press('Enter');
  await expect(first).toContainText('confirmed');
  const reviewed=await exported();
  expect(reviewed.source).toEqual(before.source);
  expect(reviewed.review_history).toHaveLength(1);
  expect(reviewed.assessment.run_id).toBeNull();
  await first.getByRole('button',{name:'Prepare Core cast proposal'}).click();
  await expect(page.getByRole('heading',{name:'Saved cast proposals'})).toBeVisible();
  expect((await exported()).source).toEqual(before.source);
  await page.evaluate(()=>window.liveSocket.disconnect());
  await expect.poll(()=>page.evaluate(()=>window.liveSocket.isConnected())).toBe(false);
  await page.evaluate(()=>window.liveSocket.connect());
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(first).toContainText('confirmed');
  await page.getByRole('button',{name:'Make reviewed proposal current'}).click();
  await expect(page.getByText('Reviewed proposal made current through typed Core acceptance.')).toBeVisible();
  const accepted=await exported();
  expect(accepted.source.revision_id).not.toBe(before.source.revision_id);
  expect(accepted.assessment.id).not.toBe(before.assessment.id);
  expect(accepted.review_history).toHaveLength(0);
  const rename=page.locator('form[phx-submit="preview_cast_rename"]').first();
  await rename.locator('input[name="rename[new_name]"]').fill('Station Guard');
  await rename.getByRole('button',{name:'Preview affected source'}).click();
  await expect(page.getByRole('heading',{name:'Prepare Station Guard'})).toBeVisible();
  await page.getByRole('button',{name:'Save proposed name change'}).click();
  await expect(page.getByText('Name change saved as a proposal. The current screenplay is unchanged.')).toBeVisible();
  expect((await exported()).source.revision_id).toBe(accepted.source.revision_id);
  expect(projectRunCount(key)).toBe(0);
});

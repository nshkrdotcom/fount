import {openWritingMenu} from './workspace_helpers.mjs';
import {test, expect} from '@playwright/test';
import {importProject, projectRunCount} from './workspace_helpers.mjs';

const source = 'Title: Writing layout\n\nINT. KITCHEN - MORNING\n\nMARA waits.\n\nEXT. PLATFORM - NIGHT #2#\n\nThe train arrives.\n';

test('writing chrome, scene margins and sticky controls remain usable at responsive breakpoints', async ({page}) => {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token');
  await page.getByRole('button', {name:'Sign in'}).click();
  const key = await importProject(page, `writing-layout-${Date.now()}`, source);
  await page.goto(`/p/${key}/write`);
  await page.getByRole('button', {name:'Save working draft'}).click();
  await page.locator('.writing-actions > summary', {hasText:/^Changes$/}).click();
  await page.getByRole('button', {name:'Save proposed change', exact:true}).click();
  await expect(page.locator('#candidate-accept')).toBeEnabled();
  await openWritingMenu(page, 'Changes');
  await page.getByRole('link', {name:'Read proposed changes', exact:true}).click();
  await expect(page).toHaveURL(/source=proposed/);
  await expect(page.locator('.named-source-picker [aria-current=page]')).toContainText('Proposed');
  await page.goto(`/p/${key}/write`);
  await page.getByRole('button', {name:'Pages', exact:true}).click();
  await expect(page.getByRole('button', {name:'Pages', exact:true})).toHaveAttribute('aria-pressed','true');
  for (const width of [390,640,641,720,768,920,921,1024,1440]) {
    await page.setViewportSize({width,height:900});
    await page.evaluate(() => scrollTo(0,0));
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
    const offsets = await page.locator('.authoring-preview-pane .screenplay-element--scene-heading').evaluateAll(elements => elements.map(e => e.querySelector('.screenplay-element__text').getBoundingClientRect().left-e.getBoundingClientRect().left));
    expect(offsets.length).toBe(2);
    for (const offset of offsets) expect(Math.abs(offset)).toBeLessThanOrEqual(1);
    await page.evaluate(() => scrollTo(0,350));
    await expect.poll(() => page.locator('#authoring-save').evaluate(e => {
      const r=e.getBoundingClientRect(); const hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);
      return !!hit && (hit===e || e.contains(hit));
    })).toBe(true);
    await page.locator('.writing-actions > summary', {hasText:/^Changes$/}).click();
    const panel=page.locator('.writing-actions[open] .writing-actions__panel');
    await expect(panel).toBeVisible();
    const r=await panel.boundingBox();expect(r.x).toBeGreaterThanOrEqual(0);expect(r.x+r.width).toBeLessThanOrEqual(width);
    await page.locator('.writing-actions > summary', {hasText:/^Changes$/}).click();
  }
  await page.emulateMedia({reducedMotion:'reduce'});
  await page.locator('.writing-actions > summary', {hasText:/^More$/}).focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#authoring-typewriter')).toBeDisabled();
  await openWritingMenu(page, 'More');
  await page.locator('#text-history > summary').click();
  await expect(page.getByRole('button',{name:'Undo text',exact:true})).toBeVisible();
  expect(projectRunCount(key)).toBe(0);
});

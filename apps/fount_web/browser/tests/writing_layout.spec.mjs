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

test('project navigation and Reading actions have symmetric vertical insets', async ({page}) => {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token');
  await page.getByRole('button', {name:'Sign in'}).click();
  const key = await importProject(page, `navigation-alignment-${Date.now()}`, source);
  for (const width of [390,640,641,720,768,920,921,1024,1440]) {
    await page.setViewportSize({width,height:900});
    await page.goto(`/p/${key}`);
    await expect(page.locator('.project-header')).toBeVisible();
    await page.evaluate(() => window.scrollTo(0, 600));
    const geometry = await page.evaluate(() => {
      const rect = e => e.getBoundingClientRect();
      const center = e => {const r=rect(e);return (r.top+r.bottom)/2;};
      const header=document.querySelector('.project-header');
      const view=document.querySelector('.project-header__view');
      const tabs=document.querySelector('.project-tabs');
      const links=[...tabs.querySelectorAll(':scope > a, :scope > details > summary')].map(rect);
      const actionLinks=[...document.querySelectorAll('.reading-primary-actions a')].map(rect);
      const first=Math.min(...actionLinks.map(r=>r.top));
      const last=Math.max(...actionLinks.map(r=>r.bottom));
      return {
        desktopHeaderOffset:center(view)-(rect(header).top+rect(header).bottom-parseFloat(getComputedStyle(header).borderBottomWidth))/2,
        viewOffsets:[...view.querySelectorAll('a')].map(e=>center(e)-center(view)),
        tabTop:Math.min(...links.map(r=>r.top))-rect(tabs).top,
        tabBottom:rect(tabs).bottom-Math.max(...links.map(r=>r.bottom)),
        actionTop:first-rect(document.querySelector('.script-context')).bottom,
        actionBottom:rect(document.querySelector('#script-search')).top-last,
        overflow:document.documentElement.scrollWidth-innerWidth
      };
    });
    if (width>920) expect(Math.abs(geometry.desktopHeaderOffset)).toBeLessThanOrEqual(0.02);
    for (const offset of geometry.viewOffsets) expect(Math.abs(offset)).toBeLessThanOrEqual(0.02);
    expect(Math.abs(geometry.tabTop-geometry.tabBottom)).toBeLessThanOrEqual(0.02);
    expect(geometry.actionTop).toBeGreaterThan(0);
    expect(Math.abs(geometry.actionTop-geometry.actionBottom)).toBeLessThanOrEqual(0.02);
    expect(geometry.overflow).toBeLessThanOrEqual(2);
  }
  expect(projectRunCount(key)).toBe(0);
});

test('Reading groups paper utilities, distinguishes active levels and keeps selection help contextual', async ({page}) => {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token');
  await page.getByRole('button', {name:'Sign in'}).click();
  const key = await importProject(page, `reader-refinement-${Date.now()}`, source);
  await page.setViewportSize({width:1440,height:900});
  await page.goto(`/p/${key}`);
  const mode=page.locator('.project-header__view [aria-current=page]');
  const destination=page.locator('.project-tabs > [aria-current=page]');
  const backgrounds=await Promise.all([mode,destination].map(el=>el.evaluate(e=>getComputedStyle(e).backgroundColor)));
  expect(backgrounds[0]).not.toBe(backgrounds[1]);
  const layout=page.getByRole('navigation',{name:'Page layout'});
  await expect(layout.locator('[aria-current=page]')).toHaveText('Responsive');
  await expect(layout.locator('[aria-disabled=true]')).toHaveText('Exported pages');
  await expect(page.getByRole('link',{name:'Build exported pages',exact:true})).toBeVisible();
  await expect(page.locator('[data-note-selection-status]')).toHaveText('');
  await page.locator('.reader-selection-help > summary').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('#passage-note-help')).toBeVisible();
  await page.locator('.reader-selection-help > summary').click();
  const scaled=await page.locator('.reader-paper .screenplay').evaluate(e=>({width:e.getBoundingClientRect().width,font:parseFloat(getComputedStyle(e).fontSize)}));
  expect(scaled.width).toBeCloseTo(784*1.08,1);
  for (const width of [390,768,1024,1440,1920]) {
    await page.setViewportSize({width,height:900});
    const r=await page.locator('.reader-utilities').boundingBox();
    expect(r.width).toBeLessThanOrEqual(784*1.08+32+1);
    expect(r.x).toBeGreaterThanOrEqual(0);expect(r.x+r.width).toBeLessThanOrEqual(width);
    expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  }
  await page.setViewportSize({width:1024,height:900});
  const standard=await page.locator('.reader-paper .screenplay').evaluate(e=>({width:e.getBoundingClientRect().width,font:parseFloat(getComputedStyle(e).fontSize)}));
  expect(scaled.width/standard.width).toBeCloseTo(1.08,2);
  expect(scaled.font/standard.font).toBeCloseTo(1.08,2);
  const passage=page.locator('.screenplay-element__text',{hasText:'MARA waits.'}).first();
  await passage.evaluate(e=>{const r=document.createRange();r.selectNodeContents(e);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(r);e.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));});
  await expect(page.locator('[data-note-selection-status]')).toContainText('Selected passage ready');
  await expect(page.getByRole('button',{name:'Note selected passage'})).toBeEnabled();
  expect(projectRunCount(key)).toBe(0);
});

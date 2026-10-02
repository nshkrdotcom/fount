import {test, expect} from '@playwright/test';
import {createHash} from 'node:crypto';
import {openWorkspace, projectRunCount, workspaceReady} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const source = 'Title: Import audit\r\n\r\nINT. ROOM - DAY\r\n\r\n' +
  'MIRA\r\nHello.\r\n\r\n'.repeat(70) +
  'A charging document reads:\r\n\r\nCOUNT ONE:\r\nVIOLENT INTERFERENCE.\r\n';

for (const width of [1440, 390]) {
  test(`large manual import exposes parser audit and bounded cue navigation at ${width}px`, async ({page, context}, testInfo) => {
    await page.setViewportSize({width, height: 900});
    await page.goto('/login');
    await page.getByLabel('Access token').fill(token);
    await page.getByRole('button', {name: 'Sign in'}).click();
    await workspaceReady(page);
    await openWorkspace(page, '/new');
    await page.locator('input[type=file]').setInputFiles({
      name: `import-audit-${width}-${Date.now()}.fountain`, mimeType: 'text/plain', buffer: Buffer.from(source)
    });
    await page.getByRole('button', {name: 'Preview import'}).click();
    await expect(page.getByText('Character identities are unverified', {exact: false})).toBeVisible();
    const consent = page.getByLabel('Assess cast & locations after import');
    if (await consent.isVisible()) await consent.uncheck();
    await page.getByRole('button', {name: 'Open screenplay'}).click();
    await expect(page).toHaveURL(/\/p\/[^/]+$/);
    await workspaceReady(page);
    const key = new URL(page.url()).pathname.split('/')[2];
    expect(projectRunCount(key)).toBe(0);
    await openWorkspace(page, `/p/${key}/cast`);
    await expect(page.locator('.compact-character-card')).toHaveCount(0);
    await expect(page.locator('#cast-cue-name option').filter({hasText: 'MIRA (70)'})).toHaveCount(1);
    await page.locator('.source-cue-group').filter({hasText: 'MIRA'}).locator('summary').first().click();
    const mira = page.locator('.source-cue-group').filter({hasText: 'MIRA'});
    await expect(mira.locator('.source-cue-occurrence')).toHaveCount(20);
    await mira.getByRole('button', {name: 'Next cues', exact: true}).click();
    await expect(mira).toContainText('Occurrence page 2');
    await page.getByLabel('Cue spelling', {exact: true}).selectOption('COUNT ONE:');
    await expect(page.locator('.compact-character-card')).toHaveCount(0);
    await expect(page.locator('.source-cue-group')).toHaveCount(1);
    await expect(page.locator('#unverified-source-cues')).toContainText('COUNT ONE:');
    await page.locator('#import-parser-audit summary').click();
    await expect(page.locator('#import-parser-audit')).toContainText('Suspected printed-text cues: 1');
    const response = await context.request.get(`/p/${key}/source-review/export.json`);
    expect(response.ok()).toBeTruthy();
    const audit = (await response.json()).import_audit;
    expect(audit.cue_occurrences).toBe(71);
    expect(audit.distinct_cue_spellings).toBe(2);
    expect(audit.semantic_confidence).toBe('unknown');
    expect(audit.source_sha256).toBe(createHash('sha256').update(source).digest('hex'));
    expect(audit.decisions.filter(row => row.rule === 'uppercase_letters_after_blank_before_nonblank')).toHaveLength(71);
    expect(projectRunCount(key)).toBe(0);
    await page.screenshot({path: testInfo.outputPath(`import-audit-${width}.png`), fullPage: true});
  });
}

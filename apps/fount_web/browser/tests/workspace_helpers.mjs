import {expect} from '@playwright/test';

export async function importProject(page, name, source) {
  await page.goto('/new');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('input[type=file]').setInputFiles({name: `${name}.fountain`, mimeType: 'text/plain', buffer: Buffer.from(source)});
  await page.getByRole('button', {name: 'Preview import'}).click();
  await expect(page.getByRole('heading', {name: `${name}.fountain`})).toBeVisible();
  await page.getByRole('button', {name: 'Open screenplay'}).click();
  await expect(page).toHaveURL(/\/p\/[^/]+$/);
  return new URL(page.url()).pathname.split('/')[2];
}

export async function createTask(page, key, journey) {
  await page.goto(`/p/${key}/work`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByLabel('Existing task').selectOption(journey);
  await page.getByRole('button', {name: 'Create task', exact: true}).click();
  await expect(page).toHaveURL(new RegExp(`/p/${key}/activity/task-1/setup$`));
  await page.getByRole('button', {name: 'Start / resume task'}).click();
}

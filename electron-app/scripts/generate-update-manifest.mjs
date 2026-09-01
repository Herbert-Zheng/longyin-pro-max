import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const projectRoot = process.cwd();
const releaseRoot = path.join(projectRoot, 'release');
const packageJson = JSON.parse(await readFile(path.join(projectRoot, 'package.json'), 'utf8'));
const zipFiles = (await readdir(releaseRoot)).filter((file) => file.toLowerCase().endsWith('.zip'));
const zipFile = `LongYinProMaxApp-${packageJson.version}-win-x64.zip`;

if (!zipFiles.includes(zipFile)) {
  throw new Error(`Expected ZIP artifact ${zipFile} was not found in ${releaseRoot}.`);
}

const unexpectedZipFiles = zipFiles.filter((file) => file !== zipFile);
if (unexpectedZipFiles.length > 0) {
  throw new Error(`Release directory contains stale ZIP artifacts: ${unexpectedZipFiles.join(', ')}`);
}
const zipPath = path.join(releaseRoot, zipFile);
const zipBuffer = await readFile(zipPath);
const sha256 = createHash('sha256').update(zipBuffer).digest('hex');

const manifest = {
  version: packageJson.version,
  zipAsset: zipFile,
  sha256,
  preservePaths: ['user-data/**', 'BepInEx/config/**']
};

await writeFile(
  path.join(releaseRoot, 'update-manifest.json'),
  `${JSON.stringify(manifest, null, 2)}\n`,
  'utf8'
);

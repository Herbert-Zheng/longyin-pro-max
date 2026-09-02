import { createHash } from 'node:crypto';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const projectRoot = process.cwd();
const releaseRoot = path.join(projectRoot, 'release');
const packageJson = JSON.parse(await readFile(path.join(projectRoot, 'package.json'), 'utf8'));
const releaseFiles = await readdir(releaseRoot);
const zipFiles = releaseFiles.filter((file) => file.toLowerCase().endsWith('.zip'));
const installerFiles = releaseFiles.filter((file) => /^LongYinProMaxSetup-.*-win-x64\.exe$/i.test(file));
const zipFile = `LongYinProMaxApp-${packageJson.version}-win-x64.zip`;
const installerFile = `LongYinProMaxSetup-${packageJson.version}-win-x64.exe`;

if (!zipFiles.includes(zipFile)) {
  throw new Error(`Expected ZIP artifact ${zipFile} was not found in ${releaseRoot}.`);
}

const unexpectedZipFiles = zipFiles.filter((file) => file !== zipFile);
if (unexpectedZipFiles.length > 0) {
  throw new Error(`Release directory contains stale ZIP artifacts: ${unexpectedZipFiles.join(', ')}`);
}
if (!installerFiles.includes(installerFile)) {
  throw new Error(`Expected Windows installer ${installerFile} was not found in ${releaseRoot}.`);
}
const unexpectedInstallerFiles = installerFiles.filter((file) => file !== installerFile);
if (unexpectedInstallerFiles.length > 0) {
  throw new Error(`Release directory contains stale Windows installers: ${unexpectedInstallerFiles.join(', ')}`);
}
const zipPath = path.join(releaseRoot, zipFile);
const installerPath = path.join(releaseRoot, installerFile);
const zipBuffer = await readFile(zipPath);
const installerBuffer = await readFile(installerPath);
const sha256 = createHash('sha256').update(zipBuffer).digest('hex');
const installerSha256 = createHash('sha256').update(installerBuffer).digest('hex');

const manifest = {
  version: packageJson.version,
  zipAsset: zipFile,
  sha256,
  installerAsset: installerFile,
  installerSha256,
  preservePaths: ['user-data/**', 'BepInEx/config/**']
};

await writeFile(
  path.join(releaseRoot, 'update-manifest.json'),
  `${JSON.stringify(manifest, null, 2)}\n`,
  'utf8'
);

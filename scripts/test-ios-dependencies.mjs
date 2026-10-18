import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const root = new URL('../', import.meta.url);
test('native scanner resolves MediaPipe without cloning its source repository', () => {
  const project = readFileSync(new URL('ios/GripIt.xcodeproj/project.pbxproj', root), 'utf8');
  assert.ok(!project.includes('XCRemoteSwiftPackageReference'), 'MediaPipe must not trigger a Git clone');
  assert.match(project, /relativePath = MediaPipeTasks;/);
  const manifest = readFileSync(new URL('ios/MediaPipeTasks/Package.swift', root), 'utf8');
  assert.match(manifest, /name: "MediaPipeTasksVision"/);
  assert.match(manifest, /755390ce853b062536899f0729321156d4cdceb263aa92c4bf3b2dd05fe640e0/);
  assert.match(manifest, /e4d88ed65c101764ef90281a411b9942f369e48673d448eff1f934e1f68d9633/);
  assert.match(manifest, /-all_load/);
});

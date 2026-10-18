// Bundle selected Lucide icons as native template SVGs. No runtime web view.
// Source: the project's pinned lucide-react package; preserve its ISC notice.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { mkdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
const icons = ['hand', 'scan-line', 'check', 'ellipsis', 'ruler', 'chevron-right', 'upload', 'arrow-right'];
for (const name of icons) {
  const { default: Icon } = await import(new URL(`node_modules/lucide-react/dist/esm/icons/${name}.js`, root));
  const folder = new URL(`ios/GripIt/Assets.xcassets/lucide-${name}.imageset/`, root);
  mkdirSync(folder, { recursive: true });
  const svg = renderToStaticMarkup(createElement(Icon, { size: 24, color: '#000000', strokeWidth: 1.75 }));
  writeFileSync(new URL(`${name}.svg`, folder), svg + '\n');
  writeFileSync(new URL('Contents.json', folder), JSON.stringify({
    images: [{ filename: `${name}.svg`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' }
  }, null, 2) + '\n');
}
copyFileSync(new URL('node_modules/lucide-react/LICENSE', root),
  new URL('ios/GripItScannerCore/Sources/GripItScannerCore/Resources/ui-lucide-license.txt', root));
console.log(`Bundled ${icons.length} Lucide SVGs in ${fileURLToPath(new URL('ios/GripIt/Assets.xcassets/', root))}`);

# Shared throw entry and feedback

The TypeScript validator and deterministic rules are the source of truth. Native SwiftUI calls the bundled JavaScriptCore entry point, so feedback works offline and uses the same rules as tests.

Run `npm run ios:focus` after any shared-code change. The generated `focus-engine.js` is committed so Xcode does not require Node. Native tests exercise that exact bundle with Step 2 reach constraints.

There is no AI chat, provider or generated coaching path. The screenshot review uses bundled readings until an image-reading service is added in a separate change.

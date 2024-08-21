# Changelog

## [1.1.1](https://github.com/stevearc/quicker.nvim/compare/v1.1.0...v1.1.1) (2024-08-20)


### Bug Fixes

* refresh replaces all item text with buffer source ([f28fca3](https://github.com/stevearc/quicker.nvim/commit/f28fca3863f8d3679e86d8ff30d023a43fba15c8))

## [1.1.0](https://github.com/stevearc/quicker.nvim/compare/v1.0.0...v1.1.0) (2024-08-20)


### Features

* better support for lazy loading ([29ab2a6](https://github.com/stevearc/quicker.nvim/commit/29ab2a6d4771ace240f25df028129bfc85e16ffd))
* display errors as virtual text when expanding context ([#16](https://github.com/stevearc/quicker.nvim/issues/16)) ([6b79167](https://github.com/stevearc/quicker.nvim/commit/6b79167543f1b18e76319217a29bb4e177a5e1ae))
* quicker.refresh preserves and display diagnostic messages ([#19](https://github.com/stevearc/quicker.nvim/issues/19)) ([349e0de](https://github.com/stevearc/quicker.nvim/commit/349e0def74ddbfc47f64ca52202e84bedf064048))


### Bug Fixes

* editor works when filename is truncated ([7a64d4e](https://github.com/stevearc/quicker.nvim/commit/7a64d4ea2b641cc8671443d0ff26de2924894c9f))
* **editor:** load buffer if necessary before save_changes ([#14](https://github.com/stevearc/quicker.nvim/issues/14)) ([59a610a](https://github.com/stevearc/quicker.nvim/commit/59a610a2163a51a019bde769bf2e2eec1654e4d4))
* error when quickfix buffer is hidden and items are added ([#8](https://github.com/stevearc/quicker.nvim/issues/8)) ([a8b885b](https://github.com/stevearc/quicker.nvim/commit/a8b885be246666922aca7f296195986a1cae3344))
* guard against double-replacing a diagnostic line ([2dc0f80](https://github.com/stevearc/quicker.nvim/commit/2dc0f800770f8956c24a6d70fa61e7ec2e102d8a))
* **highlight:** check if src_line exists before trying to highlight it ([#6](https://github.com/stevearc/quicker.nvim/issues/6)) ([b6a3d2f](https://github.com/stevearc/quicker.nvim/commit/b6a3d2f6aed7882e8bea772f82ba80b5535157a9))
* include number of files in editor message ([#13](https://github.com/stevearc/quicker.nvim/issues/13)) ([7d2f6d3](https://github.com/stevearc/quicker.nvim/commit/7d2f6d33c7d680b0a18580cfa5feb17302f389d4))
* missing highlight groups for headers ([5dafd80](https://github.com/stevearc/quicker.nvim/commit/5dafd80225ba462517c38e7b176bd3df52ccfb35))
* prevent error when treesitter parser is missing ([#4](https://github.com/stevearc/quicker.nvim/issues/4)) ([5cc096a](https://github.com/stevearc/quicker.nvim/commit/5cc096aad4ba1c1e17b6d76cb87fd7155cf9a559))
* show filename for invalid items ([#11](https://github.com/stevearc/quicker.nvim/issues/11)) ([514817d](https://github.com/stevearc/quicker.nvim/commit/514817dfb0a2828fe2c6183f996a31847c8aa789))

## 1.0.0 (2024-08-07)


### Bug Fixes

* guard against race condition in syntax highlighting ([#1](https://github.com/stevearc/quicker.nvim/issues/1)) ([03d9811](https://github.com/stevearc/quicker.nvim/commit/03d9811c8ac037e4e9c8f4ba0dfd1dff0367e0ac))

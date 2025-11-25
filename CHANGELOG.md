# Changelog

## [1.5.0](https://github.com/stevearc/quicker.nvim/compare/v1.4.0...v1.5.0) (2025-11-25)


### Features

* add QuickFixTextInvalid highlight group ([#44](https://github.com/stevearc/quicker.nvim/issues/44)) ([1798be7](https://github.com/stevearc/quicker.nvim/commit/1798be71cdcb15fb84fa8054148a56e17fd391dc))


### Bug Fixes

* defer lazy loading hack ([191b487](https://github.com/stevearc/quicker.nvim/commit/191b487d3e915389e9f0e6e3e5c19746d5b71bf2))
* potential infinite loop for inconsistent buffer state ([9983d4b](https://github.com/stevearc/quicker.nvim/commit/9983d4b28881e1df626e3682167b45c284d4da8c))
* prevent adding duplicate events for the same buffer ([#57](https://github.com/stevearc/quicker.nvim/issues/57)) ([51d3926](https://github.com/stevearc/quicker.nvim/commit/51d3926f183c2d98fbc237cc237ae0926839af3a))
* replace deprecated nvim_err_writeln with nvim_echo ([7349ca2](https://github.com/stevearc/quicker.nvim/commit/7349ca233d3238ab8e19a3d197f9c9438af52e96))


### Performance Improvements

* speed up :Refresh for large quickfix lists ([38177c7](https://github.com/stevearc/quicker.nvim/commit/38177c7eaaab92bcd07698badcf315239d3ec161))
* speed up save for large quickfix lists ([6b88ca4](https://github.com/stevearc/quicker.nvim/commit/6b88ca4d70e35df877d9564beba83f00ba0c3133))

## [1.4.0](https://github.com/stevearc/quicker.nvim/compare/v1.3.0...v1.4.0) (2025-02-12)


### Features

* add view option to open(), change handling of height option ([#38](https://github.com/stevearc/quicker.nvim/issues/38)) ([b9b7eec](https://github.com/stevearc/quicker.nvim/commit/b9b7eec8dc56bd653ae342caa5400a4e5ba3529c))


### Bug Fixes

* change default highlight.load_buffers to false ([#39](https://github.com/stevearc/quicker.nvim/issues/39)) ([ceff21e](https://github.com/stevearc/quicker.nvim/commit/ceff21e3c715499cd1aba02321fdacaee8250875))
* don't enforce window height for full-height vsplit quickfix ([049def7](https://github.com/stevearc/quicker.nvim/commit/049def718213d3cdf49fdf29835aded09b3e54a3))
* hide filename when max_filename_width = 0 ([#36](https://github.com/stevearc/quicker.nvim/issues/36)) ([e4fb0b1](https://github.com/stevearc/quicker.nvim/commit/e4fb0b1862284757561d1d51091cdee907585948))
* highlights when trim_leading_whitespace = 'all' ([87dae0f](https://github.com/stevearc/quicker.nvim/commit/87dae0f25733b7bd79b600a70ca38040db68ec0b))

## [1.3.0](https://github.com/stevearc/quicker.nvim/compare/v1.2.0...v1.3.0) (2024-12-24)


### Features

* add option to remove all leading whitespace from items ([#26](https://github.com/stevearc/quicker.nvim/issues/26)) ([da7e910](https://github.com/stevearc/quicker.nvim/commit/da7e9104de4ff9303e1c722f7c9216f994622067))
* option to scroll to closest quickfix item ([#23](https://github.com/stevearc/quicker.nvim/issues/23)) ([cc8bb67](https://github.com/stevearc/quicker.nvim/commit/cc8bb67271c093a089d205def9dd69a188c45ae1))
* toggle function for context ([#18](https://github.com/stevearc/quicker.nvim/issues/18)) ([049d665](https://github.com/stevearc/quicker.nvim/commit/049d66534d3de5920663ee1b8dd0096d70f55a67))


### Bug Fixes

* filter vim.NIL when deserializing buffer variables ([#30](https://github.com/stevearc/quicker.nvim/issues/30)) ([a3cf525](https://github.com/stevearc/quicker.nvim/commit/a3cf5256998f9387ad8e293c6f295d286be6453f))

## [1.2.0](https://github.com/stevearc/quicker.nvim/compare/v1.1.1...v1.2.0) (2024-11-06)


### Features

* add command modifiers to the `toggle()` and `open()` APIs ([#24](https://github.com/stevearc/quicker.nvim/issues/24)) ([95a839f](https://github.com/stevearc/quicker.nvim/commit/95a839fafff1c0a7fe970492f5159f41a90974bf))


### Bug Fixes

* crash in highlighter ([11f9eb0](https://github.com/stevearc/quicker.nvim/commit/11f9eb0c803bb9ced8c6043805de89c62bd04515))
* guard against out of date buffer contents ([1fc29de](https://github.com/stevearc/quicker.nvim/commit/1fc29de2172235c076aa1ead6f1ee772398de732))
* trim_leading_whitespace works with mixed tabs and spaces ([#26](https://github.com/stevearc/quicker.nvim/issues/26)) ([46e0ad6](https://github.com/stevearc/quicker.nvim/commit/46e0ad6c6a1d998a294e13cbb8b7c398e140983a))

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

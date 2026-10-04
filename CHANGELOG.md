# Changelog

## [0.5.0](https://github.com/bottrall/acp-sdk/compare/v0.4.0...v0.5.0) (2026-10-04)


### Features

* add authenticate and logout to ACP::ClientConnection ([#63](https://github.com/bottrall/acp-sdk/issues/63)) ([460585a](https://github.com/bottrall/acp-sdk/commit/460585a9a9401e35725ea379432694d9b76f35b6))
* add session_set_mode and session_set_config_option to ACP::ClientConnection ([#66](https://github.com/bottrall/acp-sdk/issues/66)) ([994179f](https://github.com/bottrall/acp-sdk/commit/994179f9ab51918bee7d29c8b473e0f05a55a7ad))
* add session/resume, session/close and session/delete to the client ([#65](https://github.com/bottrall/acp-sdk/issues/65)) ([4af834a](https://github.com/bottrall/acp-sdk/commit/4af834a5bc519753bad36d41efba902bcddc296b)), closes [#37](https://github.com/bottrall/acp-sdk/issues/37)
* elicitation on ACP::AgentConnection::Client ([#67](https://github.com/bottrall/acp-sdk/issues/67)) ([7d3212a](https://github.com/bottrall/acp-sdk/commit/7d3212a82ec6392351d8df1349b2fc21bf0bf030)), closes [#41](https://github.com/bottrall/acp-sdk/issues/41)
* filesystem handlers on ACP::ClientConnection ([#68](https://github.com/bottrall/acp-sdk/issues/68)) ([053f091](https://github.com/bottrall/acp-sdk/commit/053f0910adc3a7016bf1769099a54655f41bb9a6))
* injectable logger for dropped messages and swallowed errors ([#59](https://github.com/bottrall/acp-sdk/issues/59)) ([e66a306](https://github.com/bottrall/acp-sdk/commit/e66a30622922717d1be6d27c5b9a2931643fcd6b))


### Bug Fixes

* call ACP::RequestError.unadvertised in elicitation capability checks ([#69](https://github.com/bottrall/acp-sdk/issues/69)) ([fda6dad](https://github.com/bottrall/acp-sdk/commit/fda6dad13e7fe308b5ff63e4c9e6fa9eef6e8274))
* only advertise terminal auth methods to clients that support them ([#61](https://github.com/bottrall/acp-sdk/issues/61)) ([1d2674a](https://github.com/bottrall/acp-sdk/commit/1d2674a978d938834d69d2c68df4f2c918ea801c)), closes [#33](https://github.com/bottrall/acp-sdk/issues/33)
* refuse overlapping streaming calls for the same session ([#64](https://github.com/bottrall/acp-sdk/issues/64)) ([a3a5b34](https://github.com/bottrall/acp-sdk/commit/a3a5b343f0ba2555b62643577226166fada27485))
* reject an unsupported protocol version in ACP::ClientConnection#connect ([#62](https://github.com/bottrall/acp-sdk/issues/62)) ([6980b32](https://github.com/bottrall/acp-sdk/commit/6980b328bcec997ae68c6af9077d623a73c15d39)), closes [#34](https://github.com/bottrall/acp-sdk/issues/34)

## [0.4.0](https://github.com/bottrall/acp-sdk/compare/v0.3.0...v0.4.0) (2026-10-02)


### Features

* bump the vendored schema to v1.24.1 ([#58](https://github.com/bottrall/acp-sdk/issues/58)) ([56d8505](https://github.com/bottrall/acp-sdk/commit/56d85057a1c34f1a089580a78b7b66973c92a9e8))


### Bug Fixes

* return a RequestError for malformed peer responses ([#57](https://github.com/bottrall/acp-sdk/issues/57)) ([e52d479](https://github.com/bottrall/acp-sdk/commit/e52d479ce8cd6de37f753e7580d5562f1ace2d7d)), closes [#27](https://github.com/bottrall/acp-sdk/issues/27)
* route logout on ACP::AgentConnection ([#55](https://github.com/bottrall/acp-sdk/issues/55)) ([3b2b144](https://github.com/bottrall/acp-sdk/commit/3b2b1444c502380a058231884c66efe26bb3770a)), closes [#26](https://github.com/bottrall/acp-sdk/issues/26)

## [0.3.0](https://github.com/bottrall/acp-sdk/compare/v0.2.0...v0.3.0) (2026-10-02)


### Features

* named protocol error codes ([#52](https://github.com/bottrall/acp-sdk/issues/52)) ([0a81700](https://github.com/bottrall/acp-sdk/commit/0a81700e3fa095279a77e2f161a7d6369c46792f))
* spawn an agent process for ACP::ClientConnection ([#54](https://github.com/bottrall/acp-sdk/issues/54)) ([e01d2d2](https://github.com/bottrall/acp-sdk/commit/e01d2d280e9cfd08c203f6dccd1ce602979e21c8))

## [0.2.0](https://github.com/bottrall/acp-sdk/compare/v0.1.0...v0.2.0) (2026-09-30)


### Features

* authenticate on ACP::AgentConnection ([#23](https://github.com/bottrall/acp-sdk/issues/23)) ([aac2bdd](https://github.com/bottrall/acp-sdk/commit/aac2bddbada2108bad3397d8f2c7bcdd617e8e0f))
* filesystem methods on ACP::AgentConnection::Client ([#20](https://github.com/bottrall/acp-sdk/issues/20)) ([a15d942](https://github.com/bottrall/acp-sdk/commit/a15d942d1fe48cd7042732f64ea6d94cdd191549)), closes [#10](https://github.com/bottrall/acp-sdk/issues/10)
* optional session methods on ACP::AgentConnection ([#24](https://github.com/bottrall/acp-sdk/issues/24)) ([952f906](https://github.com/bottrall/acp-sdk/commit/952f906e32bf455bac40effeb3d32fa6dea95904))
* terminal methods on ACP::AgentConnection::Client ([#22](https://github.com/bottrall/acp-sdk/issues/22)) ([b4108b8](https://github.com/bottrall/acp-sdk/commit/b4108b8570a36d78a2c1231c04f7c1f697848318))

## 0.1.0 (2026-09-30)


### Features

* ACP::AgentConnection with the required methods, session/load and session/list ([#14](https://github.com/bottrall/acp-sdk/issues/14)) ([565798c](https://github.com/bottrall/acp-sdk/commit/565798cffa6a0a3a09c38d28fa2cc25db881650e))
* ACP::ClientConnection ([#17](https://github.com/bottrall/acp-sdk/issues/17)) ([65fc83a](https://github.com/bottrall/acp-sdk/commit/65fc83a8cda8896c03090fe4bb59a59907418791)), closes [#6](https://github.com/bottrall/acp-sdk/issues/6)
* JSON-RPC over NDJSON stdio transport with mid-turn multiplexing ([#9](https://github.com/bottrall/acp-sdk/issues/9)) ([ef5f7db](https://github.com/bottrall/acp-sdk/commit/ef5f7db50f4272161f010f14dd99e49f2526d68b))
* vendor the ACP schema.json and generate the types ([#8](https://github.com/bottrall/acp-sdk/issues/8)) ([69c6ece](https://github.com/bottrall/acp-sdk/commit/69c6ece77ff1b785c8f7f20681e3af71a1cbaffa)), closes [#3](https://github.com/bottrall/acp-sdk/issues/3)

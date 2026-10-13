# Changelog

## [0.13.0](https://github.com/bottrall/acp-sdk/compare/v0.12.0...v0.13.0) (2026-10-13)


### ⚠ BREAKING CHANGES

* the ACP::Transport::_Transport, ACP::Transport::_Peer, ACP::ClientConnection::Streams::_Sender and ACP::AgentConnection::_Client interfaces no longer exist. Name ACP::Transport::Stdio and ACP::AgentConnection::Client instead.

### Features

* type transport and client seams as concrete classes ([#149](https://github.com/bottrall/acp-sdk/issues/149)) ([89805a0](https://github.com/bottrall/acp-sdk/commit/89805a0a462701a9528a059a63dc5147ba2285c2))

## [0.12.0](https://github.com/bottrall/acp-sdk/compare/v0.11.0...v0.12.0) (2026-10-13)


### Features

* add RequestError#connection_closed? predicate ([#145](https://github.com/bottrall/acp-sdk/issues/145)) ([16692be](https://github.com/bottrall/acp-sdk/commit/16692be92531e2ddbf14d6547a1bbb431cc151d3)), closes [#108](https://github.com/bottrall/acp-sdk/issues/108)
* expose Stdio serving state and drain ([#148](https://github.com/bottrall/acp-sdk/issues/148)) ([e8169c1](https://github.com/bottrall/acp-sdk/commit/e8169c1902d8f8ab185cc809e14f08ea98300007)), closes [#107](https://github.com/bottrall/acp-sdk/issues/107)

## [0.11.0](https://github.com/bottrall/acp-sdk/compare/v0.10.0...v0.11.0) (2026-10-12)


### Features

* standardize ClientConnection senders on verb-noun naming ([#118](https://github.com/bottrall/acp-sdk/issues/118)) ([1b844ec](https://github.com/bottrall/acp-sdk/commit/1b844ecccef5b8714c5e3f2d0299713f0ee09e0f))


### Bug Fixes

* answer malformed elicitation params as invalid params ([#133](https://github.com/bottrall/acp-sdk/issues/133)) ([b9e1c51](https://github.com/bottrall/acp-sdk/commit/b9e1c510b60f78986998ba8be56c8a039488ee95)), closes [#125](https://github.com/bottrall/acp-sdk/issues/125)
* answer the agent when a permission handler raises ([#134](https://github.com/bottrall/acp-sdk/issues/134)) ([a0f61a9](https://github.com/bottrall/acp-sdk/commit/a0f61a9db3589848fafadb7b4e19ad70b260f508)), closes [#124](https://github.com/bottrall/acp-sdk/issues/124)
* cancel the echo agent's in-flight turn when its session is closed or deleted ([#136](https://github.com/bottrall/acp-sdk/issues/136)) ([e04a8c0](https://github.com/bottrall/acp-sdk/commit/e04a8c0bb672b569d68029c63eaee826d00c84fd)), closes [#130](https://github.com/bottrall/acp-sdk/issues/130)
* **codegen:** keep the unset sentinel out of clearable to_h conversions ([#140](https://github.com/bottrall/acp-sdk/issues/140)) ([67769d7](https://github.com/bottrall/acp-sdk/commit/67769d7ff5d9f93dfe3f3ea2ba4ac71126caad60)), closes [#131](https://github.com/bottrall/acp-sdk/issues/131)
* **codegen:** resolve primitive unions from each option's resolved shape ([#141](https://github.com/bottrall/acp-sdk/issues/141)) ([0b574ae](https://github.com/bottrall/acp-sdk/commit/0b574ae9d33c6c10eb0a00866b6c07f1601e01e8)), closes [#132](https://github.com/bottrall/acp-sdk/issues/132)
* **codegen:** subsume union-variant twins into variant aliases ([#103](https://github.com/bottrall/acp-sdk/issues/103)) ([bdc0005](https://github.com/bottrall/acp-sdk/commit/bdc0005460c0fd133a09f10cf61f9f5717012e16)), closes [#93](https://github.com/bottrall/acp-sdk/issues/93)
* echo slash commands followed only by whitespace ([#135](https://github.com/bottrall/acp-sdk/issues/135)) ([bb4bde6](https://github.com/bottrall/acp-sdk/commit/bb4bde6951ceb54ac87c92ec335dcdd319fd7b81)), closes [#129](https://github.com/bottrall/acp-sdk/issues/129)
* read mcpCapabilities alone when deciding whether MCP is advertised ([#139](https://github.com/bottrall/acp-sdk/issues/139)) ([a6e882e](https://github.com/bottrall/acp-sdk/commit/a6e882ebf3c69f0aa8692100e81e61a085007a8b)), closes [#128](https://github.com/bottrall/acp-sdk/issues/128)
* return a null or false result instead of "Connection closed" ([#137](https://github.com/bottrall/acp-sdk/issues/137)) ([19be64d](https://github.com/bottrall/acp-sdk/commit/19be64df6064e370bb23614a3b8df1056649cd3b)), closes [#127](https://github.com/bottrall/acp-sdk/issues/127)
* settle a pending request when its response is malformed ([#138](https://github.com/bottrall/acp-sdk/issues/138)) ([7d0586e](https://github.com/bottrall/acp-sdk/commit/7d0586e856a54e5779e4d523bd0862ab57f44b10)), closes [#126](https://github.com/bottrall/acp-sdk/issues/126)

## [0.10.0](https://github.com/bottrall/acp-sdk/compare/v0.9.0...v0.10.0) (2026-10-07)


### Features

* MCP-over-ACP mcp/message (unstable) ([#89](https://github.com/bottrall/acp-sdk/issues/89)) ([3d6d30c](https://github.com/bottrall/acp-sdk/commit/3d6d30c6e31e88dd0fe78e08a5bc4308948cacdd))
* providers/list, providers/set and providers/disable (unstable) ([#88](https://github.com/bottrall/acp-sdk/issues/88)) ([eac16f7](https://github.com/bottrall/acp-sdk/commit/eac16f78809ea5a677835c6fe064063dcb64c162)), closes [#50](https://github.com/bottrall/acp-sdk/issues/50)
* request cancellation on the agent and client connections ([#85](https://github.com/bottrall/acp-sdk/issues/85)) ([58ae0ab](https://github.com/bottrall/acp-sdk/commit/58ae0abe6387e2887482ec14e361cfac91cd54ea))
* session/fork (unstable) ([#86](https://github.com/bottrall/acp-sdk/issues/86)) ([9868cb6](https://github.com/bottrall/acp-sdk/commit/9868cb666a8111c414bf3b041167d6aa022e1e95)), closes [#49](https://github.com/bottrall/acp-sdk/issues/49)
* support all currently supported Ruby versions ([#90](https://github.com/bottrall/acp-sdk/issues/90)) ([343d07b](https://github.com/bottrall/acp-sdk/commit/343d07b9e6d98b1c24201c5eef8b250858c0626b)), closes [#73](https://github.com/bottrall/acp-sdk/issues/73)

## [0.9.0](https://github.com/bottrall/acp-sdk/compare/v0.8.0...v0.9.0) (2026-10-07)


### Features

* $/cancel_request in ACP::Transport::Stdio ([#82](https://github.com/bottrall/acp-sdk/issues/82)) ([8679883](https://github.com/bottrall/acp-sdk/commit/86798837ce9e35949c7cc3770e52f3191d81bc6f))
* opt-in types for the unstable schema ([#83](https://github.com/bottrall/acp-sdk/issues/83)) ([a49a5cc](https://github.com/bottrall/acp-sdk/commit/a49a5ccba84e599fc8fae95fe2336a4eb3169835))

## [0.8.0](https://github.com/bottrall/acp-sdk/compare/v0.7.0...v0.8.0) (2026-10-06)


### Features

* elicitation handlers on ACP::ClientConnection ([#78](https://github.com/bottrall/acp-sdk/issues/78)) ([94ee653](https://github.com/bottrall/acp-sdk/commit/94ee65374a0b463ccbd7ed57e05fe1ad76b08a62))


### Bug Fixes

* validate primitive and enum types when parsing params ([#79](https://github.com/bottrall/acp-sdk/issues/79)) ([624be63](https://github.com/bottrall/acp-sdk/commit/624be63f667468fba7c1a61064b84f43c226b060))

## [0.7.0](https://github.com/bottrall/acp-sdk/compare/v0.6.0...v0.7.0) (2026-10-05)


### Features

* terminal handlers on ACP::ClientConnection ([#77](https://github.com/bottrall/acp-sdk/issues/77)) ([8a42829](https://github.com/bottrall/acp-sdk/commit/8a428295d5cd7c92b56ec1b3ed1c900b485bbf01)), closes [#40](https://github.com/bottrall/acp-sdk/issues/40)


### Bug Fixes

* attach data to method-not-found and invalid-request replies ([#75](https://github.com/bottrall/acp-sdk/issues/75)) ([9bc201c](https://github.com/bottrall/acp-sdk/commit/9bc201c53d86f506bedb5b49183b865cf9b8f4fe)), closes [#29](https://github.com/bottrall/acp-sdk/issues/29)
* don't send handler exception messages to the peer ([#74](https://github.com/bottrall/acp-sdk/issues/74)) ([af66b48](https://github.com/bottrall/acp-sdk/commit/af66b48cbab4a99244c28a9c6f6a12c9ea23efc7)), closes [#28](https://github.com/bottrall/acp-sdk/issues/28)

## [0.6.0](https://github.com/bottrall/acp-sdk/compare/v0.5.0...v0.6.0) (2026-10-04)


### Features

* answer pending permission requests with cancelled after session_cancel ([#70](https://github.com/bottrall/acp-sdk/issues/70)) ([06a218b](https://github.com/bottrall/acp-sdk/commit/06a218b6262ff409e301d08a43330af5b60837e0))
* extension methods on both connections ([#72](https://github.com/bottrall/acp-sdk/issues/72)) ([d1faa1a](https://github.com/bottrall/acp-sdk/commit/d1faa1a738019e73a4dbad5b59f480795f8dd4bf))

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

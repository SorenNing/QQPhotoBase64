# QQPhotoBase64 0.1.1：参考发送路径调整（未构建）

用户确认上传的 QQEncTweak_v4_source.zip 对应源码“能实现发送”。其发送函数先尝试 picker `context` KVC → `AIFileManager sendFileWithPath:uin:uid:chatType:`，不满足时提供用户手动分享加密文件。此反馈没有区分哪条分支最终发出；当前插件不应将“参考源码能发送”直接等同“直发已实测”。

## 当前生产候选

- 保留静态图片 Base64 JSON `.qqenc`，不引入参考包 AES/密码/视频或不同的 `QQENC1\n` 格式；仍拦截勾选状态下原图片发送。
- 只有当当前 picker 存在完整对象返回 ABI 的 `context` getter，读回真实 `AIOChatContext` 时，才快照 peerUin、peerUid、chatType，并在每个文件调用前核对同一 picker、上下文对象和参数。QQ 文件接口返回 void，仅表示调用，不保证送达。
- 不直接对未确认 Swift weak 字段执行 KVC；`@catch` 不能捕获原生内存错误。没有经确认的 getter 或发送接口不匹配、且**未调用过**直发接口时，仅提供用户确认的“分享编码文件”选项；分享的是逐文件验证过的 Base64 JSON，不包括原图。已有文件可能已交给 QQ 时绝不自动分享，以免重复。
- 上一版实验性 setter/Swift weak bridge、C 元数据解析器和 fixture 文件仍在仓库供审查，但不参与此候选生产构建/测试。`QQPShare.m` 也仍作为旧实现保留，不参与生产构建。
- 当前 QQ 9.3.86.617 资料仅列 `setContext:`，未证明 `context` getter 存在；因此**直发可能仍不触发，仅能走手动分享**。参考源码可发送的用户实测不等价于当前插件已实测。是否曾经通过 KVC 安全读到实际 Swift weak `context` 仍未知，不能据此绕过门控。

## 验证与许可

前一次授权的 run 43659427064 在 Mac Swift fixture 执行阶段 `Trace/BPT trap: 5`，iOS dylib/deb 未生成；那次许可已耗尽。当前改动的 QQPChat.m、QQPPlugin.m 已完成 arm64/arm64e 严格语法四项零诊断，脚本及源码路径检查通过；CI 和 QQ 真机尚待，不得称直发已成功。工作流仅 `workflow_dispatch`，源码同步不会自动构建；新构建仍须新单次许可，默认 64 普通无根 + 64e RootHide。

未构建新 deb、未安装/注入/发送/注销/发布或更新软件源。已发布的 0.1.0 仍走旧转发确认。

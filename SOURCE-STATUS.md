# 当前聊天直发修复候选

本次源码完成了当前聊天直发候选实现，尚未有新安装包。不能将本地 C/ObjC 检查等同 Apple Swift 编译或 QQ 真机成功。

## 实现

- 原生相册发送回调在编码前捕获聊天目标；导出完成后按同一相册、binding、owner、context、三元组逐文件核对，再调用 `AIFileManager sendFileWithPath:uin:uid:chatType:`。旧 `QQPShare.m` 作为历史文件保留，但不在当前构建输入中。
- `setContext:` 一次性 hook 为每次赋值创建新 binding；回读须与 QQ 实际保存对象同一身份，不能只使用 setter 参数。非主线程赋值只使对应相册失效。
- 有 `context` getter 时要求完整对象 ABI；没有 getter 时由 Swift 读取指定声明层、精确字段名的存储。weak 只在字段类型编码证明其 ownership 后才读取；真正的 weak load 交给 Swift runtime。
- C 解析器接受的完整类型语法有限：直接 symbolic class reference + `SgXw`，或单 protocol reference + `_pSgXw` / `_XlSgXw`。符号引用的四字节 payload 可含 NUL，不能当普通字符串。unknown/间接引用/泛型/其他 existential 编码拒绝。尚未证实目标 QQ 实际使用哪一形态。
- `W` property 属性不足以区分 Swift weak/unowned，本实现不依赖它做 ownership 决定。拒绝 unowned/unowned(unsafe) 与嵌套、追加的伪 weak 后缀。
- 身份只从白名单 `AIOChatContext` 读取；controller owner 的 `chatContext` 必须是 strong 对象字段。当前校验要求 peerUin、peerUid 均非空，其他身份组合尚未验证。
- 保留静态图片 Base64 JSON 格式，不采用参考包的 AES/密码/视频或 `QQENC1\n` 格式。

## 已执行

- QQPRuntime.m、QQPChat.m、QQPPlugin.m、QQPWeakField.c × arm64/arm64e：8 项 strict syntax exit 0，零诊断；检查前后输入 SHA256 一致。
- 生产 C 字段解析器：34 项正反 fixture 测试通过，只读测试内存，不是 QQ 或 Swift runtime 测试。
- 生产对象编码检查函数：18 项正反例通过。
- 构建/测试 shell 语法、Python 解析、差异空白检查通过。

## 尚未执行

- Apple Swift 编译与实际桥接 fixture（已接 `tools/test-macos.sh`）：继承层、Optional、weak 替换/清空/消失、protocol weak、unowned 拒绝、相邻 dangling unowned。
- 完整 iOS 双架构链接、签名、安装包生成及最终包检查。
- QQ 9.3.86.617 的实际字段元数据/加载、当前聊天提交、接收及取消实测。

GitHub workflow 仅手动 dispatch。源码同步不会触发构建；下一次构建需单次许可，默认同时生成普通无根 64 与 RootHide 64e。没有自动安装、注入、注销或更新软件源。

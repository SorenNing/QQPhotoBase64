# qqEncryption

作者：Ning · 版本：1.0.1 · iOS 15+

包标识：`com.ning.qqencryption`。迁移自 `com.ning.qqphotobase64`，包声明替换并冲突旧标识，避免两份插件并存。用户选定的企鹅头像仅通过软件源的 `Icon` URL 用于 Sileo，不包含在 deb 中，不添加设置页或修改 QQ 界面。

QQ 相册底栏在“原图”旁加入圆圈“加密”开关。勾选后将选择的静态图片编码为既有 `.qqenc` JSON 文件，MP4/MOV/M4V 视频编码为新 `QQENC2` 流式 Base64 `.qqenc` 文件；仅在当前聊天对象可被安全核实时直发，整批交给 QQ 后关闭相册返回聊天。失败仍显示原因且不会改发未编码原视频。QQ 文件详情页在“用其他应用打开”上方显示“解密”，解码后在 QQ 内预览图片或播放视频，不使用系统 Quick Look。

**Base64 是可逆编码，不提供保密性。** 本版没有 AES、密码或密钥。SHA256 用来检测文件损坏，不提供发送者认证。

## 使用

1. 在 QQ 相册选择 1–9 项静态图片或视频，勾选“加密”，再点原发送按钮。
2. 等待资源导出。仅当当前相册存在已核对返回类型的 `context` getter，且对象属于 `AIOChatContext`，才尝试 `AIFileManager sendFileWithPath:uin:uid:chatType:`；提交前再次核对。整批调用无异常时只关闭当前相册返回聊天，不代表 QQ 已上传或对方已收到。同版 QQ 若没有该 getter，将弹出“分享编码文件”选项，必须由用户手动确认目标，不会自动向当前聊天发送。
3. 接收方先完整下载 `.qqenc`，在 QQ 文件详情点“解密”：图片在 QQ 内预览，视频在 QQ 内播放。双方均需插件支持，旧版 0.1.2 无法解码新 QQENC2 视频。
4. 关闭“加密”时保留 QQ 的普通图片发送路径。勾选状态下若选图接口不匹配或导出失败，停止此次发送并显示原因。

支持 JPEG、PNG、HEIC、HEIF 单帧图片，以及原始资源为 MP4、MOV、M4V 的视频；最多选 9 项，图片原始资源每项最多 32MiB。视频没有插件设定的大小上限，使用固定缓冲流式编解码，但受设备空间、文件系统、QQ 文件发送接口及服务器限制。视频编码后约比原文件大三分之一，编码和解码期间需容纳原文件、容器及解码文件。不处理 GIF、Live Photo。支持 Photos 允许的 iCloud 资源下载；离开相册时取消未完成的相册导出。编码文件保存在 QQ 缓存目录，过期清理；已提交的文件保留给 QQ 异步读取，未提交的失败导出会清理。

## 兼容性状态

目标是 `com.tencent.mqq`。QQ 私有接口采用运行时方法签名检查，不匹配时不安装对应 Hook。用户实测 0.1.1 可从相册提交文件，并能在 QQ 文件详情页解密、进入系统预览；0.1.2 的三项 UI 改动尚未设备验证。语法、容器和签名校验不能代替 QQ 真机兼容性验证。新版 QQ 使用不同控制器、选图模型、底栏或迟加载类时，入口可能不出现。

## 构建与包

GitHub Actions 仅允许 `workflow_dispatch`，使用 `macos-latest`。顺序为源码 SHA256 清单核对、Apple 平台生产 codec 测试、Apple clang 双架构分别编译与 ad-hoc 签名、按对应架构分别打包、代码页/特殊槽/包结构检查、最终包提取后 `codesign --verify --strict --all-architectures`。

- `iphoneos-arm64`：只含 arm64 动态库，普通无根 `/var/jb/Library/MobileSubstrate/DynamicLibraries/`。
- `iphoneos-arm64e`：只含真 arm64e 动态库（subtype `0x80000002`），RootHide loader 使用的 `Library/MobileSubstrate/DynamicLibraries/` 布局，需相应越狱环境的加载器支持。

0.1.4 仅将两包各自重复的另一架构移出，不删图片、视频或播放器功能。各包独立签名，包架构必须与唯一 Mach-O 架构一致。两包标识相同，不要同时安装。签名检查不代表 Apple 信任签名，也不证明设备加载器兼容。本工程不自动安装、注入、注销或发布到软件源。

Mac 本地命令：

```sh
python3 tools/verify_source.py
bash tools/test-macos.sh
bash tools/build-macos.sh
python3 tools/verify.py
python3 tools/verify_packages_macos.py dist/*.deb
```

`tests/codec_test.m` 直接链接生产 `QQPCodec.m`，检查已知摘要、原字节往返、恰好 32MiB 的合法 PNG 及损坏输入。旧 Swift 弱字段读取和测试保留为研究资料，不属于当前生产构建。`tools/verify.py` 不依赖第三方 Python 包，最终检查报告在 `build/` 和 `dist/`。

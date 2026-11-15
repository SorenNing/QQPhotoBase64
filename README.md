# QQPhotoBase64 / QQ图片编码

作者：Ning · 版本：0.1.0 · iOS 15+

QQ 相册底栏在“原图”旁加入圆圈“加密”开关。勾选后将选择的静态图片原始资源编码为 `.qqenc` JSON 文件，向本次相册所属聊天提交文件请求。当前源码为直发修复候选，尚未完成 Apple Swift 编译及 QQ 真机验证；已发布 0.1.0 包仍为旧转发确认实现。QQ 文件详情页遇到 `.qqenc` 文件显示“解密”，下载完整后可用 QuickLook 预览还原的图片。

**Base64 是可逆编码，不提供保密性。** 本版没有 AES、密码或密钥。SHA256 用来检测文件损坏，不提供发送者认证。

## 使用

1. 在 QQ 相册选择 1–9 张静态图片，勾选“加密”，再点原发送按钮。
2. 等待资源导出。源码候选从当前相册回读 `context`，核对 setter 绑定及具体聊天对象，再调用 `AIFileManager sendFileWithPath:uin:uid:chatType:`；无法确认归属就停止。接口返回 void，仅表示调用结束，实际发送状态需在聊天中查看。
3. 接收方先完整下载 `.qqenc`，在 QQ 文件详情点“解密”。双方均需插件支持。
4. 关闭“加密”时保留 QQ 的普通图片发送路径。勾选状态下若选图接口不匹配或导出失败，停止此次发送并显示原因。

支持 JPEG、PNG、HEIC、HEIF 单帧图片；每张原始资源最多 32MiB、最多 5000 万像素、单边最多 16384 像素。不处理视频、GIF、Live Photo。支持 Photos 允许的 iCloud 资源下载；离开相册时取消未完成的导出。编码文件保存在 QQ 缓存目录，过期清理；已提交的文件保留给 QQ 异步读取，未提交的失败导出会清理。

## 兼容性状态

目标是 `com.tencent.mqq`。QQ 私有接口采用运行时方法签名检查，不匹配时不安装对应 Hook。当前候选接口来自 QQ 9.3.86.617 的接口资料；尚未在该 QQ 版本上完成发送、接收、取消或视觉验证。语法、容器和签名校验通过不能代替真机兼容性验证。新版 QQ 使用不同控制器、选图模型、底栏或迟加载类时，入口可能不出现。

## 构建与包

GitHub Actions 仅允许 `workflow_dispatch`，使用 `macos-latest`。顺序为源码 SHA256 清单核对、Apple 平台生产 codec 测试、Apple clang 双架构编译、lipo、ad-hoc 签名、双布局打包、代码页/特殊槽/包结构检查、最终包提取后 `codesign --verify --strict --all-architectures`。

- `iphoneos-arm64`：普通无根 `/var/jb/Library/MobileSubstrate/DynamicLibraries/`。
- `iphoneos-arm64e`：RootHide loader 使用的 `Library/MobileSubstrate/DynamicLibraries/` 布局，需相应越狱环境的加载器支持。

两包内含同一份 arm64 + 真 arm64e 胖二进制，包标识相同，不要同时安装。签名检查不代表 Apple 信任签名，也不证明设备加载器兼容。本工程不自动安装、注入、注销或发布到软件源。

Mac 本地命令：

```sh
python3 tools/verify_source.py
bash tools/test-macos.sh
bash tools/build-macos.sh
python3 tools/verify.py
python3 tools/verify_packages_macos.py dist/*.deb
```

`tests/codec_test.m` 直接链接生产 `QQPCodec.m`，检查已知摘要、原字节往返、恰好 32MiB 的合法 PNG 及损坏输入。`tests/weak_field_test.c` 测试实际字段所有权解析器；它只接受完整、受限的 symbolic-reference + Optional + weak 类型语法，其他编码会停止直发。`tests/context_fixture.swift` 调用生产 Swift 读取器，覆盖继承层、strong/weak、协议 weak、nil/替换、拒绝 unowned 与相邻失效 unowned；这个 Apple 测试已接入下一次构建，但当前尚未执行。`tools/verify.py` 不依赖第三方 Python 包，最终检查报告在 `build/` 和 `dist/`。

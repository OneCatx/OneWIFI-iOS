# OneWIFI Android 独立客户端范围

## 五行范围

- 谁：通过 OneWIFI Go 服务管理设备、通信、网络与自动任务的管理员。
- 核心场景：配置服务地址并登录 → 查看真实设备与服务状态 → 对有权限且设备支持的能力执行受控操作并看到真实结果。
- 成功标准：Android 独立应用可以安装；认证会话、设备概览和后续完成矩阵中的移动端适用模块均调用 WEB 现存接口；空态、失败、无权限、过期、离线与提交状态可见；界面统一采用 OneIms Ultra 的 One 家族视觉语言。
- 非目标：不修改 WEB 后端；不修改 OneIms Ultra 源树；不复制 MethodChannel/EventChannel、SIM/Root/Shizuku/激活业务；不虚构缺失接口或本地成功。HTTP 契约见 `docs/http-api.md`。
- 截止：持续推进到冻结验收全部通过，或只剩账号、真实 Android 设备、签名材料或产品语义决策才能解除的硬阻塞。

## 技术假设

| 层 | 选定方案 | 原因 |
| --- | --- | --- |
| 框架 | Flutter 3.44.9 独立 application，仅生成 Android 平台 | 用户明确指定 Flutter Android；不得生成 add-to-app module，也不得带入 Windows 壳层 |
| 语言 | Dart 3.12.2；Android 宿主 Kotlin | 与本机稳定 Flutter 工具链一致 |
| 状态 | 显式 SessionState、QueryState<T>、ActionState，由 Controller 暴露 | 状态枚举来自冻结需求，便于测试迟到响应、刷新和重复提交 |
| 网络 | `package:http` 1.6.0 + AbortableRequest，endpoint 只存在于模块 API | 本机已有锁定源码且支持取消；不在页面拼路径 |
| 安全存储 | `flutter_secure_storage` 11.0.0 | pub.dev 当前包已核验；Bearer token 只进入平台安全存储 |
| 视觉 | OneWIFI 自有命名空间中的 One 黑白 token、GlassBackdrop、GlassPanel、StatusHero、GlassDock | 只迁移只读 OneIms 视觉行为，不建立运行时依赖 |
| 数据库 | 不需要 | 所有业务状态来自远端真实 WEB 服务 |
| 部署 | 本地 APK 构建；生产发布不在本轮授权内 | 签名、商店与生产分发需要额外材料或授权 |

## 首个可验证竖切

第一批必须贯通“启动恢复会话 → 未登录显示 One 风格登录 → 真实登录 → 进入 Android 壳 → 真实概览 → 登出清除 token”。生成脚手架本身不算交付；该竖切具备 RED→GREEN 测试、调试 APK 和错误态证据后才完成。


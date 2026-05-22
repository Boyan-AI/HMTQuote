# HMTQuote

HMTQuote 是一个面向 HarmonyOS 的 T 型报价示例工程，核心能力由 `common_sideslipview` HAR 提供。主工程用于展示业务接入、交互效果和性能验证，不作为正式应用发布模板。

## 核心能力

- Canvas 视口级 T 型报价渲染
- 行情增量更新与高频刷新调度
- 横向、纵向滚动和父容器手势协同
- 最新价定位、排序、主题和点击回调
- Example 页面与性能测试入口

## 项目结构

- `common_sideslipview/`：长期维护的 HAR 组件库
- `entry/`：业务接入示例和性能测试应用
- `docs/`：架构、性能报告和业务接入资料

## 构建

项目使用 DevEco Studio 配套的 HarmonyOS SDK 与 Hvigor 工具链。命令行构建示例：

```shell
hvigorw assembleHap --no-daemon
```

仓库不包含任何本机签名证书、Profile、密钥库或口令。需要安装到真机时，请在本地 DevEco Studio 中配置个人调试签名，且不要将生成的签名材料提交到版本库。

## 文档

- [HAR 接入说明](common_sideslipview/README.md)
- [组件架构](docs/common-sideslipview-architecture.md)
- [业务接入指南](docs/tcanvas-business-integration-guide.md)
- [性能优化摘要](docs/quote-table-performance-summary.md)

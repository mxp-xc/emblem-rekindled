# Domain docs

本仓库采用 single-context 布局：

- 根目录 `GLOSSARY.md`：领域术语。
- `docs/adr/`：架构决策记录。

## 阅读规则

探索代码前，阅读已有的 `GLOSSARY.md`，以及与当前工作相关的 ADR。
文件或目录不存在时直接继续；由 domain-modeling 在术语或决策
明确后按需创建。

## 术语和决策

issue、设计建议、假设和测试名称中的领域概念使用 glossary 定义的术语，
遵循其中对同义词的约定。

所需概念尚未收录时，先判断是否引入了项目未使用的说法；
确有术语缺口时，留给 domain-modeling 处理。

建议与已有 ADR 冲突时，明确指出对应 ADR、冲突内容和重新讨论的理由。

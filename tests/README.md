# 回归

安装 Python 与 lupa：python -m pip install lupa

准备 Moon v0.2.43（或 v0.2.45）及 KOReader v2026.07 源码。
设置 MOON_TEST_SOURCE 为 Moon 源码根目录（包含 tests 和 book.koplugin）。
设置 KOREADER_TEST_SOURCE 为 KOReader 源码根目录（包含 frontend）。
运行 python tests/run.py，报告写入 test-results.json。

使用真实 Moon 控件、首页、图书馆、侧栏、图片队列与 KOReader
LineWidget/BottomContainer；主机设备、字体、网络、文件和 ReaderUI /
ReaderRolling 入口有测试桩，不能代替 Kobo 实机开书测试。

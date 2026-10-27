# moonflow 回归

需要 Python 与 lupa（LuaJIT 2.1）。设置 MOON_TEST_SOURCE 为月读源码根目录，
包含 book.koplugin 和 tests。运行 python tests/run.py；报告写入 test-results.json。

官方彩色兼容使用 Moon 提交 033b6a3777f4d35a22e0a4d435b41960f2ef156b，
另验证 Moon 0.2.43 的灰度兼容。包括实际 Moon 一言缓存与离线回退逻辑。
字体、设备、ReaderUI/ReaderRolling、网络和文件系统有边界桩，不替代 Kobo 实机验证。

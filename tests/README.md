# 回归

需要 Python 与 lupa（LuaJIT 2.1）。设置 MOON_TEST_SOURCE 为月读源码根目录，
内含 book.koplugin 和 tests，运行 python tests/run.py。

彩色兼容使用 Moon 提交 033b6a3777f4d35a22e0a4d435b41960f2ef156b，
同时检查 Moon 0.2.43 的灰度兼容。报告写入 test-results.json。
测试使用真实 Moon 主题、控件与插件逻辑；字体、设备、ReaderUI/ReaderRolling、
网络与文件系统是边界桩，不代表 Kobo 实机刷新和耗时。

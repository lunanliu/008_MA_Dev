# CFO-FRONTDATA007 独立复核

结论：限定数据提取与整数关系范围通过。70个源文件、22个发布文件、19案例全部核验；1152920个复数H乘积、1406个z窗口和与独立phase74数据一致；222个原始窗口逐段回查原输入。

19例的系数矩阵完全相同，共8个复数系数值，因此可研究无损3位索引ROM；尚未将该压缩实现为RTL。

v1错误调用H5Dget_layout，v2查询chunk存储长度时崩溃，v3改用H5Dread_chunk和zlib解压后完成。失败记录保留，未重跑任何MATLAB或Vivado。v3以未压缩块长度分配读缓冲，仅此冻结数据范围通过；不把它批准为适用任意压缩块的通用读入器。

运行11.832秒，峰值working set125059072字节。该采集器没有记录PrivateUsage峰值，不能把working set写成私有提交。详见INDEPENDENT_REVIEW.json。

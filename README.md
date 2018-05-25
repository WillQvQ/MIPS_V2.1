# MIPS_V2.1——多周期64位CPU

[TOC]

### 一、项目概述

由于大量的前期调研和采用参数化构建模式，将32位多周期MIPS改进为64位就显得不是那么困难了。我只改动了以下七个文件就完成了任务：

```
mem.sv          修改参数N=64，设定了写双字、写字和写位的操作
mips.sv         增加了一条输出的双字/单字选择的控制信号
controller.sv   增加控制类型的信号的位数
maindec.sv      controls拓展到22位，在状体机上增加了LD，LWU，SD，DADD，DSUB，DADDI这六条指令
aludec.sv       增加了一些对双字的运算控制，将alucontrol拓展到4位
datapath.sv     修改参数N=64，修改了部分信号的拼接方式
alu.sv          修改参数N=64，增加了一些双字的运算，alucontrol拓展到4位
```

最终我的项目支持：

1. LD，LWU，LW，LBU，LB，SD，SW，SB 共8种读写指令
2. ADD，SUB，OR，AND，SLT，DADD，DSUB，NOP* 共8种R类指令
3. ADDI，ANDI，ORI，SLTI，DADDI 共5种I类计算指令
4. BEQ，BNE，J 共3种分支、跳转指令

*：根据官方文档\<MIPS64-Vol2\>，NOP 指令实际上是SLL r0, r0, 0，所以也属于R类指令

对于整个系统的详细介绍在MIPS_V2.0的实验报告中已经有了，这份报告中主要介绍一下我改进的地方。

### 二、项目文件

根目录（/）

```
/test/                  存放各种版本的汇编文件(.s)、十六进制文件(.dat)
/images/                存放实验报告所需的图片(.png)
/source/                源代码(.sv)
/Reference/             MIPS64官方文档等参考资料
.gitignore              git配置文件
memfile.dat             当前使用的十六进制文件（每行两条指令）
states.txt              Nexys4实验板演示说明
MIPS32实验报告.md        MIPS32的实验报告
README.md               说明文档
Nexys4DDR_Master.xdc    Nexys4实验板引脚锁定文件
simulation_behav.wcfg   仿真波形图配置文件
```

源代码（/source/）

```
alu.sv                  ALU计算单元
aludec.sv               ALU控制单元，用于输出alucontrol信号
clkdiv.sv               时钟分频模块模块，用于演示
controller.sv           mips的控制单元，包含maindec和aludec两部分
datapath.sv             数据通路，mips的核心结构
flopenr.sv              时钟控制的可复位触发寄存器
flopr.sv                可复位触发寄存器
maindec.sv              主控单元
mem.sv                  指令和数据的混合存储器
mips.sv                 mips处理器的顶层模块
mux2.sv                 2:1复用器
mux3.sv                 3:1复用器
mux4.sv                 4:1复用器
mux5.sv                 5:1复用器
onboard.sv              在Nexys4实验板上测试的顶层模块
regfile.sv              寄存器文件
signext.sv              符号拓展模块
simulation.sv           仿真时使用的顶层模块
sl2.sv                  左移2位
top.sv                  包含mips和内存的顶层模块
zeroext.sv              零拓展模块
```

### 三、存储器拓展

在修改N=64后，我们还需要改变存储器中读写数据的代码：

1. 读数据的时候增加了信号dword表示读取的是否为双字。因为MIPS64的指令仍然是32位的，大部分的数据操作也应该和单字相关，所以同时支持两种读取方式是比较有效率的；
2. 写数据的时候，用memwrite信号拓展到两位，为了与我写的MIPS32相兼容，仍然是1表示写单字，2表示写单Byte，新增了memwrite=3表示写双字。具体的操作上和32位有一定区别，但也不难实现。

**详细代码见mem.sv**

### 四、寄存器与ALU拓展

根据官方文档\<MIPS64-Vol1.pdf\>的描述，MIPS64的32位寄存器和64位寄存器共用空间和命名，相同名称的32位寄存器是对应64位寄存器的低32位。所以我们的寄存器代码不需要任何改动，只需要数据通路中选择参数为64。

我的ALU代码使用的是简化版本，只支持线性计算操作。从32位改到64位的时候只需要增加一位alu_control ，最高位为1的为原单字运算对应的双字运算。实际上，根据官方文档\<MIPS64-Vol2.pdf\>，双字运算只包含DADD, DADDI, DSUB等与ADD, ADDI, SUB对应的指令，而没有DAND, DSLT, DOR等指令。所以在alu_control 的编码上，我们还有更好的选择。但这里为了兼容我自己的32位版本，我没有做改动alu_control的编码。

**详细代码见alu.sv**

### 五、状态机与控制信号拓展

在状态机上，我增加了LD，LWU，SD，DADDI等指令对应的状态，而双字的R运算则与单字的R运算状态完全相同。全部指令的状态变化如下表所示，其中不同指令公用的状态在上下连续时使用‘...’表示。可以看到：读写指令有着公用的EX阶段；读指令有着公用的WB阶段；I类计算指令也有着公用的WB阶段。

| 指令  | IF   | ID   | EX       | MEM     | WB       |
| ----- | ---- | ---- | -------- | ------- | -------- |
| RTYPE | IF   | ID   | EX_RTYPE |         | WB_RTYPE |
|       |      |      |          |         |          |
| LD    | ...  | ...  | EX_LS    | MEM_LD  | WB_L     |
| LWU   | ...  | ...  | ...      | MEM_LWU | ...      |
| LW    | ...  | ...  | ...      | MEM_LW  | ...      |
| LBU   | ...  | ...  | ...      | MEM_LBU | ...      |
| LWU   | ...  | ...  | ...      | MEM_LB  | WB_L     |
| SD    | ...  | ...  | ...      | MEM_SD  |          |
| SW    | ...  | ...  | ...      | MEM_SW  |          |
| SB    | ...  | ...  | EX_LS    | MEM_SB  |          |
|       |      |      |          |         |          |
| BEQ   | ...  | ...  | EX_BEQ   |         |          |
| BNE   | ...  | ...  | EX_BNE   |         |          |
| J     | ...  | ...  | EX_J     |         |          |
|       |      |      |          |         |          |
| DADDI | ...  | ...  | EX_DADDI |         | WB_I     |
| ADDI  | ...  | ...  | EX_ADDI  |         | ...      |
| ANDI  | ...  | ...  | EX_ANDI  |         | ...      |
| ORI   | ...  | ...  | EX_ORI   |         | ...      |
| SLTI  | IF   | ID   | EX_SLTI  |         | WB_I     |

在控制信号上，主要将readtype(原来叫ltype)的位数增加为3位，用000表示读取Signed Word，001表示读取Unsigned Word，010表示写读取Signed Byte，011表示写读取Unsigned Byte,100表示读取Double Word。其中readtype的最高位还可以输出到mem里面控制是否读双字。全部控制信号的含义如下

```
memwrite[1:0]       写存储器的类型，0表示不写，1表示写Word，2表示写Byte,3表示写DoubleWord
pcwrite             用于计算pcen，pcen最后决定是否更新pc
irwrite             决定从存储器读出的数据是否当作指令进行译码
regwrite            是否写寄存器
alusrca             决定ALU的第一个运算数
branch              是否分支,用于计算pcen
iord                决定了从存储器读出的为指令还是数据
memtoreg            是否有从存储器到寄存器的数据存储
regdst              是否为R类指令
bne                 是否为bne指令,用于计算pcen
alusrcb[2:0]        决定ALU的第二个运算数
pcsrc[1:0]          决定下一个pc的计算方式
aluop[2:0]          决定了alu计算的方式，传给aludec进行具体的控制
readtype[2:0]       读存储器的类型，
```

**详细代码见maindec.sv**

### 六、数据通路拓展

数据通路上主要就是修改N=64，但其中有一点需要注意的是：在64位MIPS系统中，读取的32位数据后需要拓展成64位。其中有两种方法，一种是符号拓展（LW）,另一种是零拓展（LWU），所以读取完数据要根据readtype信号从五个拓展后的数据中选取一个，这一块的代码如下：

```verilog
/* datapath.sv */
mux4    #(B)    lbmux(readdata[31:24], readdata[23:16], readdata[15:8],
                     readdata[7:0], aluout[1:0], mbyte);
zeroext #(B,N)  lbze(mbyte, mbytezext);
signext #(B,N)  lbse(mbyte, mbytesext);
zeroext #(W,N)  lwze(readdata[31:0], mwordzext);
signext #(W,N)  lwse(readdata[31:0], mwordsext);
mux5    #(N)    datamux(mwordsext,mwordzext,mbytesext,mbytezext,readdata,readtype,memdata);
```

**我在ftp上传的版本中没有添加LWU指令。而LW指令实际上实现成了LWU指令，是一个明显的错误。但由于测试数据中没有直接读取负数单字，所以没有发现这个错误**

### 七、仿真测试

我使用三个测试程序对我的64位MIPS进行测试，前两个程序与32位测试程序相同，主要用于测试兼容性，不过.dat文件要改成每行16个十六进制数的形式，类似于下面的形式：

```
20020006dc430042
9044003700832820
a04500390064302c
0064382060c6000d
0043402efc460042
fc480052fc47004a
0000000000000000
0000000001020304
0000001100000011
00000000ffffffff
```

我的第三个测试程序如上，前六行对应下面十二条汇编指令，后四行为数据，用于读写操作。

```assembly
# testls.s
main:   addi $2,$0,6    # $2=6
        ld   $3,66($2)  # $3 = 0xffffffff
        lbu  $4,55($2)  # $4 = 2
        add  $5,$4,$3   # $5 = 0x1
        sb   $5,57($2)  # sb
        dadd  $6,$3,$4  # $6 = 0x100000001
        add  $7,$3,$4   # $7 = 0x1
        daddi $6,$6,13  # $6 = 0x10000000e
        dsub  $8,$2,$3  # $8 = 0xffffffff00000007
        sd   $6,66($2)  # sd
        sd   $8,82($2)  # sd
        sd   $7,74($2)  # sd

```

我的仿真波形图如下，可以看到我们的CPU成功读取了72位置上双字，61位置上的Byte，（拓展后）相加取出低位存到63位置；然后我们分别用DADD和ADD指令相r3和r4，可以看到DADD成功地计算出了结果（结果变为100000001），而ADD指令造成了溢出（结果变为1）。后面我们还可以看到daddi，dsub和sd指令都得到了正确的结果。

![testls](/images/testls.png)

我在这个版本中还修改了simulation.sv中的部分代码，使其可以成功检测三组测试代码的顺利运行，或者运行了过长时间未结束：

```verilog
/*simulation.sv*/
always @(negedge clk) begin
        if (memwrite) begin
            if (dataadr === 100 & writedata === 7)begin
                $display("Test-standard2 pass!");
                #100  $stop;
            end
            if (dataadr === 128 & writedata === 7)begin
                 $display("Test-power2 pass!");
                 #100 $stop;
            end            
            if (dataadr === 80 & writedata === 1)begin
                 $display("Test-loadstore pass!");
                 #100 $stop;
            end
        end
        cnt = cnt + 1;
        if(cnt === 512)begin
            $display("Some error occurs!");
            $stop;
        end
    end
```

### 八、实验板演示

我在实验板演示上没有增加新的功能，所以只能通过查看地址上两个单字的值来查看双字，演示的主要功能如下：

1. 重置程序；暂停/继续程序
2. 四倍速与常速两种运行速度
3. 显示PC值、状态机的状态
4. 显示时钟周期数
5. 通关开关查看特定寄存器的部分值（最低的Byte）
6. 通过开关查看内存中任意地址的值（按字来查看）
7. 当内存被写入时，显示特殊文字突出

**因为回寝室没有实验板了，所以这一块代码没有改动了。我计划在64位流水线上尝试适合64位系统的演示方式**

### 九、时钟与资源

从时钟上看，MIPS64与MIPS32一致

![Timing](/images/Timing.png)
从资源占用上看，MIPS64的LUT大约是MIPS32的两倍，其他资源占用基本一致

**MIPS64**

![Utilization64](/images/Utilization64.png)

**MIPS32**

![Utilization32](/images/Utilization32.png)

### 十、参考资料

1. <a href="/Reference/MIPS64-Vol1.pdf">MIPS64-Vol1.pdf</a>
2. <a href="/Reference/MIPS64-Vol2.pdf">MIPS64-Vol2.pdf</a>
3. <a href="MIPS32实验报告.md">多周期32位CPU实验报告</a>


# MIPS_V2.1——多周期64位CPU

姓名 学号

[TOC]

### 一、项目概述

由于大量的前期调研和采用参数化构建模式，将32位多周期MIPS改进为64位就显得不是那么困难了。我只改动了以下七个文件就完成了任务：

```
mem.sv          修改参数N=64，设定了写双字、写字和写位的操作
mips.sv         增加了一条输出的控制信息
controller.sv   增加了一条输出的控制信息
maindec.sv      controls拓展到22位，在状体机上增加了几条指令的状态
aludec.sv       增加了一些对双字的运算控制，alucontrol拓展到4位
datapath.sv     修改参数N=64，修改了部分信号的拼接方式
alu.sv          修改参数N=64，增加了一些双字的运算，alucontrol拓展到4位
```

对于整个系统的详细介绍在MIPS_V2.0的实验报告中已经有了，这份报告中主要介绍一下我改进的地方。

### 二、项目文件

根目录（/）

```
/test/                  存放各种版本的汇编文件(.s)、十六进制文件(.dat)
/images/                存放实验报告所需的图片(.png)
/source/                源代码(.sv)
/MIPS64/                MIPS64官方文档
.gitignore              git配置文件
memfile.dat             当前使用的十六进制文件
states.txt              Nexys4实验板演示说明
MIPS32.md               MIPS32的说明文档
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

<div STYLE="page-break-after: always;"></

### 三、存储器拓展

在修改N=64后，我们还需要改变存储器中读写数据的代码：读数据的时候增加了信号readtype（0表示读单字，1表示读双字），因为MIPS64的指令仍然是32位的，大部分的数据操作也应该和单字相关；写数据的时候，与我写的MIPS32相兼容，用memwrite信号来进行控制，仍然是1表示写单字，2表示写单Byte，新增了memwrite=3表示写双字。具体的操作和32位也有一定区别，但也不难实现。

```verilog
/*mem.sv*/
module mem#(parameter N = 64, L = 128)(
    input   logic           clk, 
    input   logic           readtype,
    input   logic [1:0]     memwrite,
    input   logic [N-1:0]   dataadr, writedata,
    output  logic [N-1:0]   readdata,
    input   logic [7:0]     checka,
    output  logic [31:0]    check
);
    logic [N-1:0] RAM [L-1:0];
    logic [31:0]  word;
    initial
        $readmemh("C:/Users/will131/Documents/workspace/MIPS_V2.1/memfile.dat",RAM);
    assign readdata = readtype ? RAM[dataadr[N-1:3]] : {32'b0,word};
    assign check = checka[0] ? RAM[checka][31:0] : RAM[checka][63:32];
    assign word = dataadr[2] ? RAM[dataadr[N-1:3]][31:0] : RAM[dataadr[N-1:3]][63:32];
    always @(posedge clk)
        begin
        if (memwrite==3)//D
            RAM[dataadr[N-1:3]] <= writedata;
        else if (memwrite==2) //B
                case (dataadr[2:0])
                    3'b111:  RAM[dataadr[N-1:3]][7:0]   <= writedata[7:0];
                    3'b110:  RAM[dataadr[N-1:3]][15:8]  <= writedata[7:0];
                    3'b101:  RAM[dataadr[N-1:3]][23:16] <= writedata[7:0];
                    3'b100:  RAM[dataadr[N-1:3]][31:24] <= writedata[7:0];
                    3'b011:  RAM[dataadr[N-1:3]][39:32] <= writedata[7:0];
                    3'b010:  RAM[dataadr[N-1:3]][47:40] <= writedata[7:0];
                    3'b001:  RAM[dataadr[N-1:3]][55:48] <= writedata[7:0];
                    3'b000:  RAM[dataadr[N-1:3]][63:56] <= writedata[7:0];
                endcase
        else if (memwrite==1) //W
                case (dataadr[2])
                    0:  RAM[dataadr[N-1:3]][63:32]  <= writedata[31:0];
                    1:  RAM[dataadr[N-1:3]][31:0]   <= writedata[31:0];
                endcase
        end 
endmodule
```

### 四、寄存器与ALU拓展

根据官方文档\<MIPS64-Vol1.pdf\>的描述，MIPS64的32位寄存器和64位寄存器共用空间和命名，相同名称的32位寄存器是对应64位寄存器的低32位。所以我们的寄存器代码不需要任何改动，只需要数据通路中选择参数为64。

我的ALU代码使用的是简化版本，只支持线性计算操作。从32位改到64位的时候只需要增加一位alu_control ，最高位为1的为对应的双字运算。实际上，根据官方文档\<MIPS64-Vol2.pdf\>，双字运算只包含DADD,DADDI,DSUB等与ADD,ADDI,SUB对应的指令，而没有DAND,DSLT,DOR等指令。所以在alu_control 的编码上，我们还有更好的选择。但这里为了兼容我自己的32位版本，我没有做改动。

### 五、控制信号与数据通路拓展

在控制信号上，64位的系统需要增加一位dtype ，表示当前处理的操作是否为双字操作；同时在alu_control 的输出上做出相应的改变，以支持DADD,DADDI,DSUB等指令。而数据通路上，将只需要将模块的整体参数N改为64，并修改如instr等几个小地方的代码即可。

我在兼容原32位的18个指令的基础上，增加了5个64位指令LD,SD,DADD,DADDI和DSUB。其中DADD和DSUB属于R类指令，不需要改动状态机，只需在aludec中增加支持即可。而LD,SD与LW,SW类似、DADDI与ADDI类似，只需仿照原来的指令设计状态即可。核心代码如下：

```verilog
/*maindec.sv*/
module maindec(
    input   logic       clk, reset,   
    input   logic [5:0] op,
    output  logic       pcwrite, 
    output  logic [1:0] memwrite, 
    output  logic       irwrite, regwrite, dtype,
    output  logic       branch, iord, memtoreg, regdst, alusrca, 
    output  logic [2:0] alusrcb,
    output  logic [1:0] pcsrc,
    output  logic [2:0] aluop,
    output  logic       bne, 
    output  logic [1:0] ltype,
    output  logic [4:0] stateshow
); 
    typedef enum logic [4:0] {IF, ID, EX_LS, MEM_LW, WB_L, 
            MEM_SW, EX_RTYPE, WB_RTYPE, EX_BEQ, EX_ADDI, EX_J,
            EX_ANDI, EX_BNE, MEM_LBU, MEM_LB, EX_ORI, EX_SLTI,
            MEM_SB, WB_I, MEM_LD, MEM_SD, EX_DADDI} statetype;
    statetype state, nextstate;
    assign stateshow = state;
    parameter RTYPE = 6'b000000;
    parameter LD    = 6'b110111;
    parameter LW    = 6'b100011;
    parameter LBU   = 6'b100100;
    parameter LB    = 6'b100000;
    parameter SD    = 6'b111111;
    parameter SW    = 6'b101011;
    parameter SB    = 6'b101000;
    parameter BEQ   = 6'b000100;
    parameter BNE   = 6'b000101;
    parameter J     = 6'b000010;
    parameter ADDI  = 6'b001000;
    parameter ANDI  = 6'b001100;
    parameter ORI   = 6'b001101;
    parameter SLTI  = 6'b001010;
    parameter DADDI = 6'b011000;
    logic [21:0] controls; 
    always_ff @(posedge clk or posedge reset) begin
        $display("State is %d",state);
        if(reset) state <= IF;
        else state <= nextstate;
    end
    always_comb
        case(state)
            IF: nextstate <= ID;
            ID: case(op)
                SD:     nextstate <= EX_LS;
                SW:     nextstate <= EX_LS;
                SB:     nextstate <= EX_LS;
                LD:     nextstate <= EX_LS;
                LW:     nextstate <= EX_LS;
                LB:     nextstate <= EX_LS; 
                LBU:    nextstate <= EX_LS; 
                RTYPE:  nextstate <= EX_RTYPE;
                J:      nextstate <= EX_J;
                BNE:    nextstate <= EX_BNE;
                BEQ:    nextstate <= EX_BEQ;
                ADDI:   nextstate <= EX_ADDI;
                ANDI:   nextstate <= EX_ANDI;
                ORI:    nextstate <= EX_ORI; 
                SLTI:   nextstate <= EX_SLTI;
                DADDI:  nextstate <= EX_DADDI; 
                default:nextstate <= IF;
            endcase
            EX_LS: case(op)
                SD:     nextstate <= MEM_SD;
                SW:     nextstate <= MEM_SW;
                SB:     nextstate <= MEM_SB;
                LD:     nextstate <= MEM_LD;
                LW:     nextstate <= MEM_LW;
                LBU:    nextstate <= MEM_LBU; 
                LB:     nextstate <= MEM_LB;
                default:nextstate <= IF;
            endcase
            MEM_LD:     nextstate <= WB_L;
            MEM_LW:     nextstate <= WB_L;
            MEM_LBU:    nextstate <= WB_L;
            MEM_LB:     nextstate <= WB_L;
            MEM_SD:     nextstate <= IF;
            MEM_SW:     nextstate <= IF;
            MEM_SB:     nextstate <= IF;
            WB_L:       nextstate <= IF;
            EX_RTYPE:   nextstate <= WB_RTYPE;
            WB_RTYPE:   nextstate <= IF;
            EX_BEQ:     nextstate <= IF;
            EX_BNE:     nextstate <= IF;
            EX_J:       nextstate <= IF;
            EX_ADDI:    nextstate <= WB_I;
            EX_ANDI:    nextstate <= WB_I; 
            EX_ORI:     nextstate <= WB_I;
            EX_SLTI:    nextstate <= WB_I;
            EX_DADDI:   nextstate <= WB_I;
            WB_I:       nextstate <= IF; 
            default:    nextstate <= IF;
        endcase
    assign {memwrite, pcwrite, irwrite, regwrite,
            alusrca, branch, iord, memtoreg, regdst,
            bne, alusrcb, pcsrc, aluop, ltype, dtype} = controls; 
    always_comb
        case(state)
            IF:         controls <= 22'b00_110_00000_0_001_00_000_000;
            ID:         controls <= 22'b00_000_00000_0_011_00_000_000;
            EX_LS:      controls <= 22'b00_000_10000_0_010_00_000_000;
            MEM_LD:     controls <= 22'b00_000_00100_0_000_00_000_001;
            MEM_LW:     controls <= 22'b00_000_00100_0_000_00_000_000;
            MEM_LB:     controls <= 22'b00_000_00100_0_000_00_000_100;
            MEM_LBU:    controls <= 22'b00_000_00100_0_000_00_000_010;
            WB_L:       controls <= 22'b00_001_00010_0_000_00_000_000;
            MEM_SD:     controls <= 22'b11_000_00100_0_000_00_000_000;
            MEM_SW:     controls <= 22'b01_000_00100_0_000_00_000_000;
            MEM_SB:     controls <= 22'b10_000_00100_0_000_00_000_000;
            EX_RTYPE:   controls <= 22'b00_000_10000_0_000_00_010_000;
            WB_RTYPE:   controls <= 22'b00_001_00001_0_000_00_000_000;
            EX_BEQ:     controls <= 22'b00_000_11000_0_000_01_001_000;
            EX_BNE:     controls <= 22'b00_000_10000_1_000_01_001_000;
            EX_J:       controls <= 22'b00_100_00000_0_000_10_000_000;
            EX_ADDI:    controls <= 22'b00_000_10000_0_010_00_000_000;
            EX_ANDI:    controls <= 22'b00_000_10000_0_100_00_011_000; 
            EX_ORI:     controls <= 22'b00_000_10000_0_100_00_100_000; 
            EX_SLTI:    controls <= 22'b00_000_10000_0_010_00_101_000; 
            EX_DADDI:   controls <= 22'b00_000_10000_0_010_00_110_000; 
            WB_I:       controls <= 22'b00_001_00000_0_000_00_000_000;
            default:    controls <= 22'b00_000_xxxxx_x_xxx_xx_xxx_xxx;
        endcase
endmodule
```

### 六、仿真测试

我使用三个测试程序对我的64位MIPS进行测试，前两个程序与32位测试程序相同，主要用于测试兼容性，不过.dat文件要改成每行16个十六进制数的形式，类似于下面的形式：

```
20020006dc430042
9044003700832820
a04500390064302c
0064382018c6000d
0043402efc460042
fc47004afc480052
0000000000000000
0000000001020304
0000001100000011
00000000ffffffff
```

我的第三个测试程序如上，前六行对应下面十二条汇编指令，后四行为数据，用于读写操作。

```assembly
# testls.s
main:   addi $2,$0,6
        ld   $3,66($2) # ld
        lbu  $4,55($2) 
        add  $5,$4,$3
        sb   $5,57($2)
        dadd  $6,$3,$4  # dadd
        add  $7,$3,$4    
        daddi $6,$6,13  # daddi
        dsub  $8,$2,$3  # dsub 
        sd   $6,66($2) 	# sd
        sd   $7,74($2) 	# sd
        sd   $8,82($2) 	# sd
```

我的仿真波形图如下，可以看到我们的CPU成功读取了72位置上双字，61位置上的Byte，（拓展后）相加取出低位存到63位置；然后我们分别用DADD和ADD指令相r3和r4，可以看到DADD成功地计算出了结果（结果变为100000001），而ADD指令造成了溢出（结果变为1）。后面我们还可以看到daddi，dsub和sd指令都得到了正确的结果。

![testls](/images/testls.png)

我在这个版本中还修改了simulation.sv中的部分代码，使其可以成功检测三组测试代码的顺利运行或者过长时间未结束：

```verilog
/*simulation.sv*/
always @(negedge clk) begin
        if (memwrite) begin
            if (dataadr === 84 & writedata === 7)begin
                $display("Test-standard2 pass!");
                $stop;
            end
            if (dataadr === 128 & writedata === 7)begin
                 $display("Test-power2 pass!");
                 $stop;
            end            
            if (dataadr === 80 & writedata === 1)begin
                 $display("Test-loadstore pass!");
                 $stop;
            end
        end
        cnt = cnt + 1;
        if(cnt === 512)begin
            $display("Some error occurs!");
            $stop;
        end
    end
```

### 七、实验板测试

实验板测试上没有增加新的功能，只能通过查看地址上两个单字的值来查看双字，演示的主要功能如下：

1. 重置程序
2. 暂停/继续程序
3. 四倍速与常速两种运行速度
4. 显示PC值、状态机的状态
5. 显示时钟周期数
6. 通关开关查看特定寄存器的部分值（最低的Byte）
7. 通过开关查看内存中任意地址的值（按字来查看）
8. 当内存被写入时，显示特殊文字突出

从时钟上看，MIPS64与MIPS32一致

![Timing](/images/Timing.png)
从资源占用上看，MIPS64的LUT大约是MIPS32的两倍，其他资源占用基本一致

**MIPS64 **

![Utilization64](/images/Utilization64.png)

**MIPS32**

![Utilization32](/images/Utilization32.png)

### 八、参考资料

1. <a href="/MIPS64/MIPS64-Vol1.pdf">MIPS64-Vol1.pdf</a>
2. <a href="/MIPS64/MIPS64-Vol2.pdf">MIPS64-Vol2.pdf</a>
3. <a href="MIPS32.md">多周期32位CPU实验报告</a>


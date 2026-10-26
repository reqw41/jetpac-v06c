#!/usr/bin/env python3
# Дизассемблер 6502 (py65) для разбора BBC-версии: tools/dis6502.py <файл> <база hex> <от hex> <до hex>
import sys
from py65.devices.mpu6502 import MPU
from py65.disassembler import Disassembler
from py65.memory import ObservableMemory
f,base,start,end=sys.argv[1],int(sys.argv[2],16),int(sys.argv[3],16),int(sys.argv[4],16)
d=open(f,'rb').read()
mpu=MPU(); mem=bytearray(0x10000); mem[base:base+len(d)]=d; mpu.memory=mem
dis=Disassembler(mpu)
pc=start
while pc<end:
    n,txt=dis.instruction_at(pc)
    print(f'{pc:04X}  {mem[pc:pc+n].hex(" "):9} {txt}')
    pc+=n

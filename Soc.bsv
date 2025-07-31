// See LICENSE.iitm for license details

package Soc;
  // project related imports
	import Semi_FIFOF:: *;
	import AXI4_Types:: *;
	import AXI4_Fabric:: *;
  import ccore:: * ;
  import ccore_types:: * ;
  import Clocks :: *;
  `include "ccore_params.defines"
  `include "Soc.defines"
  // peripheral imports
  import uart::*;
  import clint::*;
  import sign_dump::*;
  import err_slave::*;
  // package imports
  import Connectable:: *;
  import GetPut:: *;
  import Vector::*;
  import bram :: *;
  `ifndef axi4_128b
  import bootrom :: *;
   `else
  import bootrom_axi4 :: *;
   `endif
  import csrbox :: * ;
`ifdef debug
  import debug_types::*;                                                                          
`endif
/start/
 // import sdram :: *;
/end/
  typedef 0 Sign_master_num;
  typedef (TAdd#(TMul#(`num_harts,2), `ifdef debug 1 `else 0 `endif )) Debug_master_num;
  typedef (TAdd#(Debug_master_num, 1)) Num_Masters;
 
    function Bit#(TLog#(`Num_Slaves)) fn_slave_map (Bit#(`paddr) addr);
      Bit#(TLog#(`Num_Slaves)) slave_num = 0;
      if(addr >= `MemoryBase && addr<= `MemoryEnd)
        slave_num = `Memory_slave_num;
      else if(addr>= `BootRomBase && addr<= `BootRomEnd)
        slave_num =  `BootRom_slave_num;
      else if(addr>= `UartBase && addr<= `UartEnd)
        slave_num = `Uart_slave_num;
      else if(addr>= `ClintBase && addr<= `ClintEnd)
        slave_num = `Clint_slave_num;
      else if(addr>= `SignBase && addr<= `SignEnd)
        slave_num = `Sign_slave_num;
    `ifdef debug
      else if(addr>= `DebugBase && addr<= `DebugEnd)
        slave_num = `Debug_slave_num;
    `endif
      else
        slave_num = `Err_slave_num;
        
      return slave_num;
    endfunction:fn_slave_map

    `ifdef rtldump
  interface Ifc_soc_sb;
    interface Sbread sbread;
    method Maybe#(CommitLogPacket) commitlog;
  endinterface
`endif

  
  interface Ifc_Soc;
  `ifdef rtldump
  interface Ifc_soc_sb soc_sb;
  `endif
    interface RS232 uart_io;
  `ifdef debug
    interface AXI4_Slave_IFC#(`paddr,`axi4_id_width ,`buswidth, USERSPACE) to_debug_master;
    interface AXI4_Master_IFC#(`paddr, `axi4_id_width, `buswidth, USERSPACE) to_debug_slave;
    method Action ma_hart_interrupts (Bit#(`num_harts) i);
    method Bit#(`num_harts) mv_harts_have_reset;
    method Bit#(`num_harts) mv_core_debugenable;
  `endif
  endinterface

  (synthesize)
  module mkSoc `ifdef debug #(Vector#(`num_harts, Reset) hartresets ) `endif (Ifc_Soc);
    let curr_clk<-exposeCurrentClock;
    let curr_reset<-exposeCurrentReset;
    /start/
   // Reg#(Bit#(32)) copy_addr <- mkReg(0);
   // Reg#(Bool) copy_done <- mkReg(False);
 //   Reg#(Bool) copy_read_pending <- mkReg(False);
  //  Reg#(Bit#(64)) copy_data <- mkReg(0);
  /end/
    
    Reset core_reset [`num_harts];
    for (Integer i = 0; i<`num_harts; i = i + 1) begin
    `ifdef debug
      core_reset[i]<- mkResetEither(hartresets[i],curr_reset);     // OR default and new_rst
    `else
      core_reset[i] = curr_reset;
    `endif
    end

    AXI4_Fabric_IFC #(Num_Masters, `Num_Slaves, `paddr, `axi4_id_width, `buswidth, USERSPACE) 
                                                    fabric <- mkAXI4_Fabric(fn_slave_map);

    Ifc_ccore_axi4 ccore[`num_harts];
    for (Integer i = 0; i<`num_harts; i = i + 1) begin
      ccore[i] <- mkccore_axi4(`resetpc, fromInteger(i), reset_by core_reset[i]);
    end

    Ifc_sign_dump signature<- mksign_dump();
	  Ifc_uart_axi4#(`paddr,`axi4_id_width ,`buswidth,0, 16) uart <- mkuart_axi4(curr_clk,curr_reset, 5, 0, 0);
    Ifc_clint_axi4#(`paddr ,`axi4_id_width, `buswidth, 0, `num_harts, 2) clint <- mkclint_axi4();
    Ifc_err_slave_axi4#(`paddr,`axi4_id_width,`buswidth,0) err_slave <- mkerr_slave_axi4;
    Ifc_bram_axi4#(`paddr,`axi4_id_width, `buswidth, USERSPACE, `Addr_space) main_memory <- mkbram_axi4(`MemoryBase,
                                                "code.mem", "MainMEM");
    /start/
    Ifc_bram_axi4#(`paddr,`axi4_id_width, `buswidth, USERSPACE, `Addr_space) trace_bram <- mkbram_axi4(`TraceBase, "", "TraceBRAM");
  
                  Ifc_bootrom_axi4#(`paddr, `axi4_id_width, `buswidth, USERSPACE, `ifdef axi4_128b 12 `else 13 `endif ) bootrom <-mkbootrom_axi4(`BootRomBase);

  `ifdef debug
    Bit#(`num_harts) lv_haveresets=0;
    Bit#(`num_harts) lv_debugenable=0;
    Wire#(Bit#(`num_harts)) wr_hart_interrupts <- mkWire();
    for (Integer i = 0; i<`num_harts; i = i + 1) begin
      lv_haveresets[i] = ccore[i].mv_core_is_reset;
      lv_debugenable[i] = ccore[i].mv_core_debugenable;
      /*doc:rule: */
      rule rl_connect_debug_interrupt;
        ccore[i].ma_debug_interrupt(wr_hart_interrupts[i]);
      endrule:rl_connect_debug_interrupt
      /*doc:rule: */
      rule rl_connect_available; 
        ccore[i].ma_debugger_available(1);
      endrule:rl_connect_available
    end
    mkConnection(clint.ma_stop_count,ccore[0].mv_stop_timer);
    //                                                       because of change in interface of devices
  `endif
    // -------------------------------- JTAG + Debugger Setup ---------------------------------- //
      
    // ------------------------------------------------------------------------------------------//
    for (Integer i = 0; i<`num_harts; i = i + 1) begin
   	  mkConnection(ccore[i].master_d,	fabric.v_from_masters[i*2+1]);
     	mkConnection(ccore[i].master_i, fabric.v_from_masters[i*2+2]);
    end
   	mkConnection(signature.master, fabric.v_from_masters[valueOf(Sign_master_num) ]);

 	  mkConnection (fabric.v_to_slaves [`Uart_slave_num ],uart.slave);
  	mkConnection (fabric.v_to_slaves [`Clint_slave_num ],clint.slave);
    mkConnection (fabric.v_to_slaves [`Sign_slave_num ] , signature.slave);
    mkConnection (fabric.v_to_slaves [`Err_slave_num ] , err_slave.slave);
  	mkConnection(fabric.v_to_slaves[`Memory_slave_num] , main_memory.slave);
  	/start/
  	mkConnection(fabric.v_to_slaves[`Trace_slave_num], trace_bram.slave);
  	//mkConnection(fabric.v_to_slaves[`Sdram_slave_num], sdram_mem.slave_mem);
        /end/
		mkConnection(fabric.v_to_slaves[`BootRom_slave_num] , bootrom.slave);



    // sideband connection
    for (Integer i = 0; i<`num_harts; i = i + 1) begin    
      mkConnection(ccore[i].sb_clint_mtip,clint.sb_clint_mtip);
      mkConnection(ccore[i].sb_clint_mtime,clint.sb_clint_mtime);
    end
    /*doc:rule: */
    rule rl_connect_plic;
      for (Integer i = 0; i<`num_harts; i = i + 1) begin
       	ccore[i].sb_plic_meip(0);
      `ifdef supervisor
        ccore[i].sb_plic_seip(0);
      `endif
      end  
    endrule:rl_connect_plic

    // rule to connect clint.msip to each of the cores
    rule rl_connect_clint_msip;
      let msip <-clint.sb_clint_msip.get();
      for (Integer i = 0; i<`num_harts; i = i + 1) begin
        ccore[i].sb_clint_msip.put(msip[i]);
      end
    endrule: rl_connect_clint_msip
/start/
//  rule rl_start_copy (!copy_done && !copy_read_pending && sdram_mem.io.osdr_init_done);
//   let ar = AXI4_Rd_Addr {
//     araddr: `MemoryBase + copy_addr,
//     arid: 0, arlen: 0, arsize: 3, arburst: 1,
//     arlock: 0, arcache: 0, arprot: 0,
//     arqos: 0, arregion: 0, aruser: 0
//   }; 
//   main_memory.slave.o_rd_addr.enq(ar);
//   copy_read_pending <= True;
//  endrule

  //rule rl_capture_data (copy_read_pending && main_memory.slave.i_rd_data.notEmpty);
  //   let r = main_memory.slave.i_rd_data.first;
//     main_memory.slave.i_rd_data.deq;
//     copy_data <= r.rdata;
//     copy_read_pending <= False;
//  endrule

 // rule rl_write_to_sdram (!copy_read_pending && copy_data != 0);
 //    let aw = AXI4_Wr_Addr {
 //      awaddr: 32'h80000000 + copy_addr,  // <-- Choose SDRAM base
 //      awid: 0, awlen: 0, awsize: 3, awburst: 1,
 //      awlock: 0, awcache: 0, awprot: 0,
 //      awqos: 0, awregion: 0, awuser: 0
 //    };
 //    let wd = AXI4_Wr_Data { wdata: copy_data, wstrb: '1, wlast: True, wuser: 0 };

   // SDRAM slave instance must be used here, example: sdram_mem.slave_mem
   // Replace sdram_mem with your actual SDRAM instance name

 //    sdram_mem.slave_mem.o_wr_addr.enq(aw);
 //    sdram_mem.slave_mem.o_wr_data.enq(wd);

   //  copy_addr <= copy_addr + 8;
  //   copy_data <= 0;

    // if (copy_addr >= 4096) copy_done <= True;
 // endrule
/end/
  `ifdef rtldump
  interface soc_sb = interface Ifc_soc_sb
    interface commitlog= ccore[0].commitlog;
    interface sbread = ccore[0].sbread;
  endinterface;
  `endif
    interface uart_io=uart.io;
  `ifdef debug
    interface to_debug_master = fabric.v_from_masters[valueOf(Debug_master_num)];
    interface to_debug_slave  = fabric.v_to_slaves[`Debug_slave_num ];
    method Action ma_hart_interrupts (Bit#(`num_harts) i);
      wr_hart_interrupts <= i;
    endmethod
    method mv_harts_have_reset = lv_haveresets;
    method mv_core_debugenable = lv_debugenable;
  `endif

      // ------------- JTAG IOs ----------------------//
      // -------------------------------------------- //
     
  endmodule: mkSoc
endpackage: Soc

// 基础单事务序列：随机地址/数据/读写/访问粒度
class ahb_base_sequence extends uvm_sequence #(ahb_transaction);
  rand bit [15:0] addr;
  rand bit [31:0] data;
  rand bit        hwrite;
  rand bit [2:0]  hsize;
  constraint c_hsize { hsize inside {[0:2]}; }
  `uvm_object_utils(ahb_base_sequence)

  function new(string name = "ahb_base_sequence");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("ahb_base_sequence", "body", UVM_LOW)
    repeat(1) begin
      ahb_transaction tr;
      tr = ahb_transaction::type_id::create("tr");
      start_item(tr);
      tr.HADDR  = {16'h0, addr};
      tr.HWDATA = data;
      tr.HTRANS = 2'h3;          // NONSEQ
      tr.HSIZE  = hsize;
      tr.HWRITE = hwrite;
      finish_item(tr);
      get_response(tr);
      tr.print();
    end
  endtask
endclass

// 场景序列：寄存器区读写
//   - 字写读 CTRL0 / CTRL1
//   - 字节写读 CTRL2（部分更新验证）
class reg_seq extends uvm_sequence #(ahb_transaction);
  `uvm_object_utils(reg_seq)
  function new(string name = "reg_seq");
    super.new(name);
  endfunction
  virtual task body();
    ahb_base_sequence seq;
    `uvm_info("reg_seq", "=== Register area test ===", UVM_LOW)
    // 写 CTRL0 = 0xDEADBEEF，回读
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0000; seq.data = 32'hDEAD_BEEF; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0000; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 写 CTRL1 = 0x12345678，回读
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0004; seq.data = 32'h1234_5678; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0004; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 字节写 CTRL2[7:0] = 0xAB，回读验证部分更新
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0008; seq.data = 32'h0000_00AB; seq.hwrite = 1'b1; seq.hsize = 3'b000;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0008; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
  endtask
endclass

// 场景序列：SRAM 存储区读写
//   - 字写读 0x20 / 0x3FC（首尾 word）
//   - 字节写读 0x100（部分更新验证）
//   - 半字写读 0x200（低半字）
class sram_seq extends uvm_sequence #(ahb_transaction);
  `uvm_object_utils(sram_seq)
  function new(string name = "sram_seq");
    super.new(name);
  endfunction
  virtual task body();
    ahb_base_sequence seq;
    `uvm_info("sram_seq", "=== SRAM area test ===", UVM_LOW)
    // word 写读 0x20（SRAM word 0）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0020; seq.data = 32'hA5A5_5A5A; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0020; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // word 写读 0x3FC（SRAM 末尾 word）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h03FC; seq.data = 32'h0F0F_F0F0; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h03FC; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // byte 写读 0x100 的 byte0
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0100; seq.data = 32'h0000_00FF; seq.hwrite = 1'b1; seq.hsize = 3'b000;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0100; seq.hwrite = 1'b0; seq.hsize = 3'b000;
    seq.start(m_sequencer);
    // half 写读 0x200（低半字）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0200; seq.data = 32'h0000_1234; seq.hwrite = 1'b1; seq.hsize = 3'b001;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0200; seq.hwrite = 1'b0; seq.hsize = 3'b001;
    seq.start(m_sequencer);
  endtask
endclass

// 场景序列：ERROR 响应测试
//   - 访问保留地址 0x1000（非法地址）
//   - 字访问未对齐地址 0x02
//   - 半字访问未对齐地址 0x201
//   - 非法 HSIZE 访问 0x00
class err_seq extends uvm_sequence #(ahb_transaction);
  `uvm_object_utils(err_seq)
  function new(string name = "err_seq");
    super.new(name);
  endfunction
  virtual task body();
    ahb_base_sequence seq;
    `uvm_info("err_seq", "=== ERROR response test ===", UVM_LOW)
    // 保留地址 0x1000 写（应返回 ERROR）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h1000; seq.data = 32'hCAFE_F00D; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 未对齐 word 写 0x02（应返回 ERROR）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0002; seq.data = 32'h1234_5678; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 未对齐 half 写 0x201（应返回 ERROR）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0201; seq.data = 32'h0000_5678; seq.hwrite = 1'b1; seq.hsize = 3'b001;
    seq.start(m_sequencer);
    // 非法 HSIZE（4'b100）读 0x00（应返回 ERROR）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0000; seq.hwrite = 1'b0; seq.hsize = 3'b100;
    seq.start(m_sequencer);
  endtask
endclass

// 场景序列：wait state 测试
//   - 通过 CTRL2[1:0] 配置 1 拍 wait，验证读写仍正确
//   - 配置 3 拍 wait，再次验证
class wait_seq extends uvm_sequence #(ahb_transaction);
  `uvm_object_utils(wait_seq)
  function new(string name = "wait_seq");
    super.new(name);
  endfunction
  virtual task body();
    ahb_base_sequence seq;
    `uvm_info("wait_seq", "=== wait state test ===", UVM_LOW)
    // 配置 wait_cycles = 1（CTRL2[1:0] = 01）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0008; seq.data = 32'h0000_0001; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 带 1 拍 wait 的 SRAM 写读
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0040; seq.data = 32'h1111_2222; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0040; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 配置 wait_cycles = 3（CTRL2[1:0] = 11）
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0008; seq.data = 32'h0000_0003; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 带 3 拍 wait 的寄存器写读
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h000C; seq.data = 32'h8888_9999; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h000C; seq.hwrite = 1'b0; seq.hsize = 3'b010;
    seq.start(m_sequencer);
    // 恢复 wait_cycles = 0
    seq = ahb_base_sequence::type_id::create("seq");
    seq.addr = 16'h0008; seq.data = 32'h0000_0000; seq.hwrite = 1'b1; seq.hsize = 3'b010;
    seq.start(m_sequencer);
  endtask
endclass
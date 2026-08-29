class ahb_monitor extends uvm_monitor;

  virtual ahb_slave_if vif;
  uvm_analysis_port #(ahb_transaction) mon_ap;

  `uvm_component_utils(ahb_monitor)

  // 地址阶段锁存（本事务地址）
  bit        m_hsel;
  bit [31:0] m_haddr;
  bit [1:0]  m_htrans;
  bit        m_hwrite;
  bit [2:0]  m_hsize;
  bit        m_pending;   // 是否存在待完成的数据阶段

  function new(string name = "ahb_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon_ap = new("mon_ap", this);
    if(!uvm_config_db#(virtual ahb_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction

  // 两拍流水采样：
  //   - 上升沿后 #1 采样（避开驱动端沿后更新的竞争）
  //   - 步骤 1：若上一拍锁存了有效事务且本拍 HREADY=1，则本拍为数据阶段
  //     完成拍，采集 HWDATA/HRDATA/HRESP 并上报
  //   - 步骤 2：若本拍 HREADY=1，锁存总线上的新地址阶段（流水线）
  task run_phase(uvm_phase phase);
    ahb_transaction tr;
    forever begin
      @(posedge vif.HCLK iff (vif.HRESETn == 1'b1));
      #1;
      // 1) 数据阶段完成检测
      if (m_pending && vif.HREADY) begin
        tr = ahb_transaction::type_id::create("tr");
        tr.HSEL   = 1'b1;
        tr.HADDR  = m_haddr;
        tr.HTRANS = m_htrans;
        tr.HWRITE = m_hwrite;
        tr.HSIZE  = m_hsize;
        if (m_hwrite) begin
          tr.HWDATA = vif.HWDATA;
        end else begin
          tr.HRDATA = vif.HRDATA;
        end
        tr.HRESP  = vif.HRESP;
        `uvm_info(get_type_name(), $sformatf("Monitored: addr: %0h write: %0b hsize: %0h data: %0h resp: %0b", tr.HADDR, tr.HWRITE, tr.HSIZE, m_hwrite ? tr.HWDATA : tr.HRDATA, tr.HRESP), UVM_MEDIUM);
        mon_ap.write(tr);
        m_pending = 0;
      end
      // 2) 地址阶段采样（流水线：HREADY 为高时锁存新地址）
      if (vif.HREADY) begin
        m_hsel    = vif.HSEL;
        m_haddr   = vif.HADDR;
        m_htrans  = vif.HTRANS;
        m_hwrite  = vif.HWRITE;
        m_hsize   = vif.HSIZE;
        m_pending = vif.HSEL && vif.HTRANS[1];
      end
    end
  endtask

endclass
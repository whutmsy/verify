git config --global http.proxy http://127.0.0.1:10808
git config --global https.proxy http://127.0.0.1:10808
git config --global --unset http.proxy
git config --global --unset https.proxy
set UVM_HOME D:/questasim64_10.6c/verilog_src/uvm-1.1d
set UVM_DPI_HOME D:/questasim64_10.6c/uvm-1.1d/win64
vlog +incdir+$UVM_HOME/src -L mtiAvm -L mtiOvm -L mtiUvm -L mtiUPF $UVM_HOME/src/uvm_pkg.sv -f filelist.f
vsim -novopt -c -do do.tcl -sv_lib $UVM_DPI_HOME/uvm_dpi work.tb
#add wave -position end sim:/tb/u_ahb_slave/*
run -all
quit -f
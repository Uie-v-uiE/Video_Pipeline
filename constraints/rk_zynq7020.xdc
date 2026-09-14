## RK-ZYNQ7020-F constraints
## Part: xc7z020clg484-2

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 50 MHz PL clock
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

## PL keys (active low)
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports key1_n]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports key2_n]

## PL LEDs
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

## HDMI TMDS
set_property -dict {PACKAGE_PIN W16 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD TMDS_33} [get_ports tmds_clk_n]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[0]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[1]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[2]}]

## ---- PL ETH PHY2 RGMII (RTL8211F @ BANK 33, 3.3V) ----
## Source: schematic page 5 BANK33
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports eth_rxc]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports eth_rx_ctl]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[2]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[3]}]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33} [get_ports eth_tx_clk]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports eth_tx_ctl]
set_property -dict {PACKAGE_PIN T21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS33} [get_ports {eth_txd[2]}]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports {eth_txd[3]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS33} [get_ports eth_mdio]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports eth_rst_n]

## RGMII RX clock from PHY (125 MHz at 1G)
create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]
set_false_path -from [get_ports eth_rst_n]
set_false_path -to [get_ports eth_rst_n]
set_false_path -to [get_ports eth_tx_clk]
set_false_path -to [get_ports eth_tx_ctl]
set_false_path -to [get_ports {eth_txd[*]}]

# CDC: eth_rxc (125M) <-> FCLK (100M) via dc_fifo — async groups
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks clk_fpga_0] \
  -group [get_clocks sys_clk]

## False paths for async controls
set_false_path -from [get_ports key1_n]
set_false_path -from [get_ports key2_n]


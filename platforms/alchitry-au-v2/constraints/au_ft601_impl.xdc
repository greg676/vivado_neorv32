# Implementation-only (IOBUF / IOB cells exist). Not used in synthesis.
# Sourced from rebuild TCL with used_in_synthesis false.
#
# Bidirectional T (tristate) is protocol-managed: the PHY always sits in
# IDLE for a full ft_clk between drive and sample. T does not need the
# same-edge tSU as DATA/WR. Timing T as a 100 MHz source-synchronous
# output was the −0.42 ns WNS on the OBUFT T pin (clock insertion + T-to-O).

set_false_path -quiet -to [get_pins -quiet -hier -filter {REF_PIN_NAME == T && NAME =~ *ft_*}]

set_property IOB FALSE [get_cells -quiet -hier -regexp {.*rxf_r_reg$}]
set_property IOB FALSE [get_cells -quiet -hier -regexp {.*txe_r_reg$}]
set_property IOB FALSE [get_cells -quiet -hier -regexp {.*data_i_r_reg(\[[0-9]+\])?$}]
set_property IOB FALSE [get_cells -quiet -hier -regexp {.*be_i_r_reg(\[[0-9]+\])?$}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*oe_n_r_reg$}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*rd_n_r_reg$}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*wr_n_r_reg$}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*data_oe_r_reg.*}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*data_o_r_reg(\[[0-9]+\])?$}]
set_property IOB TRUE [get_cells -quiet -hier -regexp {.*be_o_r_reg(\[[0-9]+\])?$}]

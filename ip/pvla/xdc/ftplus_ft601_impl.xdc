# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# PVLA IP-scoped implementation-only (IOBUF / IOB cells exist).
# used_in_synthesis = false. Same packing as PR #18 au_ft601_impl.xdc:
# input FFs stay in fabric (7-series IOB ZHOLD); output IOB FFs kept.
# T (tristate) is a protocol false path — ALWAYS_DRIVE uses OBUF.

set_false_path -quiet -to [get_pins -quiet -hier -filter {REF_PIN_NAME == T}]
set_false_path -quiet -from [get_cells -quiet -hier -regexp {.*data_oe_r_reg.*}] \
    -to [get_ports {ft_data[*] ft_be[*]}]

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

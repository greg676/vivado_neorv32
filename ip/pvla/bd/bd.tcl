# PVLA Block Design hooks.
# Auto-promote FT601 pads to the BD wrapper with the XDC port names so the
# user never draws those nets. Probe ports stay on the canvas to wire.

proc init { cellpath otherInfo } {}

proc post_config_ip { cellpath otherInfo } {}

proc propagate { cellpath otherInfo } {}

proc post_propagate { cellpath otherInfo } {
  pvla_promote_ft601 $cellpath
}

proc pvla_promote_ft601 { cellpath } {
  if {[catch {get_property CONFIG.C_PHY [get_bd_cells $cellpath]} phy]} {
    return
  }
  if {$phy != 0} {
    return
  }
  set pins {
    ft_clk ft_wakeup ft_reset ft_rxf ft_txe ft_oe ft_rd ft_wr ft_be ft_data
  }
  foreach p $pins {
    set pin [get_bd_pins -quiet $cellpath/$p]
    if {$pin eq ""} {
      continue
    }
    if {[get_bd_nets -quiet -of_objects $pin] ne ""} {
      continue
    }
    # Same names as ip/pvla/xdc/ftplus_ft601_*.xdc
    catch { make_bd_pins_external -name $p $pin }
  }
}

"""Build can0-enable.dtbo: enables Zynq PS CAN0 (/axi/can@e0008000).

Equivalent DTS:
    /dts-v1/; /plugin/;
    / { fragment@0 { target-path = "/axi/can@e0008000";
                     __overlay__ { status = "okay"; }; }; };
Clocks (can_clk, pclk) are already defined in the base zynq-7000 tree.
The CAN reference clock is raised from the 8 MHz boot default to 100 MHz
(clkc phandle 1, clock 19 = can0) so 1 Mbps gets 20 time quanta per bit:
                     assigned-clocks = <1 19>; assigned-clock-rates = <100000000>;
"""
import fdt

tree = fdt.FDT()
tree.header.version = 17
frag = fdt.Node("fragment@0")
frag.append(fdt.PropStrings("target-path", "/axi/can@e0008000"))
ov = fdt.Node("__overlay__")
ov.append(fdt.PropStrings("status", "okay"))
ov.append(fdt.PropWords("assigned-clocks", 1, 19))
ov.append(fdt.PropWords("assigned-clock-rates", 100_000_000))
frag.append(ov)
tree.add_item(frag)

with open("can0-enable.dtbo", "wb") as f:
    f.write(tree.to_dtb(version=17))
print(tree.to_dts())

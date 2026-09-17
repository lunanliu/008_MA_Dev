# Independent module measurement assumption, not an NI platform constraint.
# clk125 is declared in clk125.xdc. All session and data ports are synchronous.
set sync_data_inputs [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_input_delay -clock clk125 -max 1.000 $sync_data_inputs
set_input_delay -clock clk125 -min 0.000 $sync_data_inputs
set_output_delay -clock clk125 -max 1.000 [all_outputs]
set_output_delay -clock clk125 -min 0.000 [all_outputs]
# reset_n is asynchronous assertion; time its release chain explicitly in review.
# No false-path masking is used in this independent measurement.

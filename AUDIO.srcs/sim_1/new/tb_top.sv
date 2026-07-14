// Testbench Code: Simulates audio input from samples.txt (signed hex 16-bit samples), generates clocks, serializes to I2S, processes through DUT, deserializes output, writes to output.txt (signed hex 16-bit)

module tb_top;

    reg clk = 0;
    reg reset_n = 0;
    reg bclk = 0;
    reg lrclk = 0;
    wire adc_sdata;
    wire dac_sdata;

    // DUT Instantiation
    top dut (
        .clk(clk),
        .reset_n(reset_n),
        .bclk(bclk),
        .lrclk(lrclk),
        .adc_sdata(adc_sdata),
        .dac_sdata(dac_sdata)
    );

    // Clock Generation (clk: 100 MHz sim, bclk: 3.072 MHz for 48kHz 64-bit frame, lrclk: 48 kHz)
    always #5 clk = ~clk;  // 100 MHz

    reg [7:0] bclk_div = 0;
    always @(posedge clk) begin
        bclk_div <= bclk_div + 1;
        if (bclk_div == 16) begin  // Approx 3.072 MHz (100M / 32.55, adjust for exact)
            bclk <= ~bclk;
            bclk_div <= 0;
        end
    end

    reg [5:0] lrclk_div = 0;
    always @(posedge bclk) begin
        lrclk_div <= lrclk_div + 1;
        if (lrclk_div == 63) begin  // 64 bits per frame (for 24-bit stereo I2S)
            lrclk <= ~lrclk;
            lrclk_div <= 0;
        end
    end

    // I2S Serialization for Input (from file samples to adc_sdata)
    reg [23:0] in_left, in_right;
    reg in_ready = 0;
    reg [4:0] in_bit_cnt = 0;
    reg in_lrclk_prev;
    assign adc_sdata = (lrclk == 0) ? in_left[23 - in_bit_cnt] : in_right[23 - in_bit_cnt];

    always @(posedge bclk) begin
        in_lrclk_prev <= lrclk;
        if (lrclk != in_lrclk_prev) in_bit_cnt <= 0;
        else if (in_bit_cnt < 23) in_bit_cnt <= in_bit_cnt + 1;
    end

    // I2S Deserialization for Output (dac_sdata to out samples)
    reg [23:0] out_left, out_right;
    reg out_valid = 0;
    reg [4:0] out_bit_cnt = 0;
    reg out_lrclk_prev;

    always @(posedge bclk) begin
        out_lrclk_prev <= lrclk;
        if (lrclk != out_lrclk_prev) begin
            out_bit_cnt <= 0;
            out_valid <= (out_lrclk_prev == 1);  // Valid on transition
        end else if (out_bit_cnt < 24) begin
            out_bit_cnt <= out_bit_cnt + 1;
            if (lrclk == 0) out_left[23 - out_bit_cnt] <= dac_sdata;
            else out_right[23 - out_bit_cnt] <= dac_sdata;
        end
    end

    // File Reading and Writing (parse signed hex 16-bit from samples.txt, output signed hex 16-bit to output.txt)
    integer in_file, out_file;
    integer num_samples = 0;
    string line;
    reg [31:0] uval;  // Temp unsigned for hex parse
    reg signed [15:0] sample_temp;
    integer parse_result;

    initial begin
        reset_n = 0;
        #20 reset_n = 1;

        // Open input .txt
        in_file = $fopen("samples.txt", "r");
        if (in_file == 0) begin
            $display("Error: Could not open samples.txt");
            $stop;
        end

        // Open output .txt
        out_file = $fopen("output.txt", "w");
        if (out_file == 0) begin
            $display("Error: Could not open output.txt");
            $stop;
        end

        // Read and process samples (interleaved left/right, signed hex 16-bit)
        while (1) begin
            // Read left sample line
            if ($fgets(line, in_file) == 0) break;
            if (line.len() == 0) continue;  // Skip empty lines
            // Remove trailing newline if present
            if (line[line.len()-1] == "\n") line = line.substr(0, line.len()-2);
            // Parse signed hex
            if (line[0] == "-") begin
                string hex_str = line.substr(1, line.len()-1);
                parse_result = $sscanf(hex_str, "%x", uval);
                if (parse_result != 1) begin
                    $display("Error: Failed to parse left sample: %s", line);
                    $stop;
                end
                sample_temp = -signed'(uval[15:0]);
            end else begin
                parse_result = $sscanf(line, "%x", uval);
                if (parse_result != 1) begin
                    $display("Error: Failed to parse left sample: %s", line);
                    $stop;
                end
                sample_temp = signed'(uval[15:0]);
            end
            in_left = {sample_temp[15:0], 8'b0};  // Left-align 16-bit to 24-bit (shift left by 8)

            // Read right sample line
            if ($fgets(line, in_file) == 0) break;
            if (line.len() == 0) continue;
            if (line[line.len()-1] == "\n") line = line.substr(0, line.len()-2);
            if (line[0] == "-") begin
                string hex_str = line.substr(1, line.len()-1);
                parse_result = $sscanf(hex_str, "%x", uval);
                if (parse_result != 1) begin
                    $display("Error: Failed to parse right sample: %s", line);
                    $stop;
                end
                sample_temp = -signed'(uval[15:0]);
            end else begin
                parse_result = $sscanf(line, "%x", uval);
                if (parse_result != 1) begin
                    $display("Error: Failed to parse right sample: %s", line);
                    $stop;
                end
                sample_temp = signed'(uval[15:0]);
            end
            in_right = {sample_temp[15:0], 8'b0};  // Left-align 16-bit to 24-bit

            in_ready = 1;
            @(posedge lrclk);  // Sync to frame
            in_ready = 0;

            // Wait for output valid
            wait (out_valid);
            // Write output samples to file (signed hex 16-bit, interleaved)
            if (out_left[23] == 1) begin
                $fwrite(out_file, "-%04X\n", -signed'(out_left[23:8]));  // Negative sample
            end else begin
                $fwrite(out_file, "%04X\n", out_left[23:8]);  // Positive sample
            end
            if (out_right[23] == 1) begin
                $fwrite(out_file, "-%04X\n", -signed'(out_right[23:8]));  // Negative sample
            end else begin
                $fwrite(out_file, "%04X\n", out_right[23:8]);  // Positive sample
            end

            num_samples = num_samples + 1;
        end

        $fclose(in_file);
        $fclose(out_file);

        $display("Simulation complete. %d samples written to output.txt", num_samples);
        $stop;
    end
endmodule
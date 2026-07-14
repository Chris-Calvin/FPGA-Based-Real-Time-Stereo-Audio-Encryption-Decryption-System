// Single Design File: Audio Processing with ADC/DAC via I2S, Two Encryption Methods

// I2S Receiver Module
module i2s_receiver (
    input bclk,
    input lrclk,
    input sdata,
    output reg [23:0] left_data,
    output reg [23:0] right_data,
    output reg data_valid
);
    reg [4:0] bit_cnt = 0;
    reg lrclk_prev;

    always @(posedge bclk) begin
        lrclk_prev <= lrclk;
        if (lrclk != lrclk_prev) begin
            bit_cnt <= 0;
            data_valid <= (lrclk_prev == 1);  // Data ready on transition
        end else if (bit_cnt < 24) begin
            bit_cnt <= bit_cnt + 1;
            if (lrclk == 0) left_data[23 - bit_cnt] <= sdata;  // MSB first
            else right_data[23 - bit_cnt] <= sdata;
        end
    end
endmodule

// I2S Transmitter Module
module i2s_transmitter (
    input bclk,
    input lrclk,
    input [23:0] left_data,
    input [23:0] right_data,
    input data_ready,
    output reg sdata
);
    reg [23:0] left_reg, right_reg;
    reg [4:0] bit_cnt = 0;

    always @(posedge bclk) begin
        if (data_ready) begin
            left_reg <= left_data;
            right_reg <= right_data;
            bit_cnt <= 0;
        end
        sdata <= (lrclk == 0) ? left_reg[23 - bit_cnt] : right_reg[23 - bit_cnt];
        if (bit_cnt < 23) bit_cnt <= bit_cnt + 1;
    end
endmodule

// Stream Cipher 1: XOR with LFSR (Polynomial: x^32 + x^22 + x^2 + x^1 + 1)
module stream_cipher1 (
    input clk,
    input reset_n,
    input [23:0] in_data,
    input data_valid,
    output reg [23:0] out_data,
    output reg out_valid
);
    reg [31:0] lfsr = 32'hACE1;  // Initial seed

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) lfsr <= 32'hACE1;
        else if (data_valid) begin
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            out_data <= in_data ^ lfsr[23:0];
            out_valid <= 1;
        end else out_valid <= 0;
    end
endmodule

// Stream Cipher 2: XOR with Different LFSR (Polynomial: x^32 + x^7 + x^5 + x^3 + 1)
module stream_cipher2 (
    input clk,
    input reset_n,
    input [23:0] in_data,
    input data_valid,
    output reg [23:0] out_data,
    output reg out_valid
);
    reg [31:0] lfsr = 32'hBEEF;  // Different seed

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) lfsr <= 32'hBEEF;
        else if (data_valid) begin
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[6] ^ lfsr[4] ^ lfsr[2] ^ lfsr[0]};
            out_data <= in_data ^ lfsr[23:0];
            out_valid <= 1;
        end else out_valid <= 0;
    end
endmodule

// Top Module (Design Under Test): Processes stereo audio, encrypts with two ciphers (chained), decrypts similarly
module top (
    input clk,          // System clock (e.g., 100 MHz for sim)
    input reset_n,
    input bclk,         // Bit clock (from testbench)
    input lrclk,        // Left/right clock (from testbench)
    input adc_sdata,    // I2S input from "ADC" (simulated)
    output dac_sdata    // I2S output to "DAC" (simulated)
);
    wire [23:0] rx_left, rx_right, enc1_left, enc1_right, enc2_left, enc2_right;
    wire [23:0] dec2_left, dec2_right, dec1_left, dec1_right;
    wire rx_valid, enc1_valid, enc2_valid, dec2_valid, dec1_valid;

    // I2S Receiver (simulates post-ADC digital stream)
    i2s_receiver rx (
        .bclk(bclk),
        .lrclk(lrclk),
        .sdata(adc_sdata),
        .left_data(rx_left),
        .right_data(rx_right),
        .data_valid(rx_valid)
    );

    // Encrypt 1 (left and right separately)
    stream_cipher1 enc1_l (.clk(clk), .reset_n(reset_n), .in_data(rx_left), .data_valid(rx_valid), .out_data(enc1_left), .out_valid(enc1_valid));
    stream_cipher1 enc1_r (.clk(clk), .reset_n(reset_n), .in_data(rx_right), .data_valid(rx_valid), .out_data(enc1_right), .out_valid(/* unused */));

    // Encrypt 2
    stream_cipher2 enc2_l (.clk(clk), .reset_n(reset_n), .in_data(enc1_left), .data_valid(enc1_valid), .out_data(enc2_left), .out_valid(enc2_valid));
    stream_cipher2 enc2_r (.clk(clk), .reset_n(reset_n), .in_data(enc1_right), .data_valid(enc1_valid), .out_data(enc2_right), .out_valid(/* unused */));

    // Decrypt 2 (same as encrypt since XOR)
    stream_cipher2 dec2_l (.clk(clk), .reset_n(reset_n), .in_data(enc2_left), .data_valid(enc2_valid), .out_data(dec2_left), .out_valid(dec2_valid));
    stream_cipher2 dec2_r (.clk(clk), .reset_n(reset_n), .in_data(enc2_right), .data_valid(enc2_valid), .out_data(dec2_right), .out_valid(/* unused */));

    // Decrypt 1
    stream_cipher1 dec1_l (.clk(clk), .reset_n(reset_n), .in_data(dec2_left), .data_valid(dec2_valid), .out_data(dec1_left), .out_valid(dec1_valid));
    stream_cipher1 dec1_r (.clk(clk), .reset_n(reset_n), .in_data(dec2_right), .data_valid(dec2_valid), .out_data(dec1_right), .out_valid(/* unused */));

    // I2S Transmitter (simulates pre-DAC digital stream)
    i2s_transmitter tx (
        .bclk(bclk),
        .lrclk(lrclk),
        .left_data(dec1_left),
        .right_data(dec1_right),
        .data_ready(dec1_valid),
        .sdata(dac_sdata)
    );
endmodule
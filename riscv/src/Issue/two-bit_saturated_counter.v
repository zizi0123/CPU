module SaturatedCounter(
    input wire branch_result, //0: not taken, 1: taken
    output wire predict_result //0: not taken, 1: taken
);
    reg [1:0] state;
    assign predict_result = state[1];
    always @(branch_result) begin
        if(branch_result == 1) begin
            if(state != 2'b11) begin
                state <= state + 1;
            end
        end
        else begin
            if(state != 2'b00) begin
                state <= state - 1;
            end
        end
    end

endmodule
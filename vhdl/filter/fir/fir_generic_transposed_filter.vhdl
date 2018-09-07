-- Author: Varun Nagpal
-- Net Id: vxn180010
-- VLSI Design Homework 1
-- 3rd Sept, 2018
--
-- Design: Generic Nth order (L = N+1 taps) Transposed FIR-filter 
-- IN:
--      n-bit sized Input samples
--      m-Bit sized coefficients
-- OUT:
--      n+m+log2(N+1)-1 bit size of output samples
--
-- Operation requires:
--      N = no. of additions
--      L = N+1 no. of taps or coefficients or multiplications
--
-- Filter must be reset everytime new coefficients have to be read
-- Once coefficients are read, input samples can be processed
-- Input and output sample is registered

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use ieee.std_logic_unsigned.all;
use work.fir_filter_shared_package.all;

-- Top level module
entity fir_generic_transposed_filter is
    generic (
            FIR_ORDER: natural := N;                               -- order of the filter (N). Note L = N+1 = taps
            XBIT_SIZE: natural := N_BITS;                          -- bit width (n) of input samples (signed 2's complement)
            HBIT_SIZE: natural := M_BITS;                          -- bit width (m) of coefficients (signed 2's complement)
            MULT_SIZE: natural := MULT_BITS;                       -- bit width (n+m) of signed multiplier
            EXTR_SIZE: natural := EXTRA_BITS;                      -- extra bits for accumulation = ceil(log2(L))-1
            YBIT_SIZE: natural := Y_BITS                           -- bit width of output samples (signed 2's complement) or signed adder
        );

    port (
        -- Clock and reset
        clk        : in  std_logic;
        rst        : in  std_logic;
        
        -- Handshaking interface as sink
        valid_x_in  : in  std_logic;                                 -- Valid input sample when acting as sink
        ready_x_out : out std_logic;                                 -- Ready for input samples when acting as sink
        valid_h_in  : in  std_logic;                                 -- Valid coefficient input when acting as sink
        ready_h_out : out std_logic;                                 -- Ready for coefficients when acting as sink

        -- Handshaking interface as source
        valid_out  : out std_logic;                                 -- Valid output when acting as source
        ready_in   : in  std_logic;                                 -- Ready input when acting as source

        --  Input samples & coefficients and Output samples
        x_data_in  : in  std_logic_vector(XBIT_SIZE-1 downto 0);    -- Input samples
        h_data_in  : in  std_logic_vector(HBIT_SIZE-1 downto 0);    -- Coefficients of filter
        y_data_out : out std_logic_vector(YBIT_SIZE-1 downto 0)     -- Output samples
    );
end fir_generic_transposed_filter;

architecture fir_rtl_arch of fir_generic_transposed_filter is
    -- N = no. of register delays or additions
    subtype ADD_REG_TYPE is std_logic_vector(YBIT_SIZE-1 downto 0);
    type ADD_REG_ARRAY is array (0 to FIR_ORDER) of ADD_REG_TYPE;

    -- L = N+1 no. of taps or coefficients or multiplications
    subtype MULT_SIG_TYPE is std_logic_vector(MULT_SIZE-1 downto 0);
    type MULT_SIG_ARRAY is array (0 to FIR_ORDER) of MULT_SIG_TYPE;
    subtype COEFF_REG_TYPE is std_logic_vector(HBIT_SIZE-1 downto 0);
    type COEFF_REG_ARRAY is array (0 to FIR_ORDER) of COEFF_REG_TYPE;

    signal adder_mem_array          : ADD_REG_ARRAY;                            -- array of L = N+1 memory (registers) blocks to store adder outputs
    signal multiplier_sigs          : MULT_SIG_ARRAY;                           -- array of L = N+1 multipler signals
    signal coefficient_mem_array    : COEFF_REG_ARRAY;                          -- array of L = N+1 memory (registers) blocks to store coefficients
    signal coeff_cnt                : integer range 0 to FIR_ORDER;             -- counter for reading L = N+1 coefficients
    signal coeff_cnt_next           : integer range 0 to FIR_ORDER;
    
    signal input_sample_mem         : std_logic_vector(x_data_in'RANGE);   -- register to store input data sample
    signal output_sample_mem        : std_logic_vector(y_data_out'RANGE);   -- register to store output data sample

    signal ready_h_out_sig          : std_logic;
    signal ready_x_out_sig          : std_logic;
    signal valid_out_sig            : std_logic;
begin
    
    -- shift coefficients
    read_coefficients: process(clk, rst)
    begin
        if (rst = '1') then
            for i in 0 to FIR_ORDER loop
                coefficient_mem_array(i) <= ( others => '0' );
            end loop;
        elsif (clk'EVENT  and clk = '1') then
            if ( ready_h_out_sig = '1' and valid_h_in = '1' ) then
                -- TBU: while reading coefficients, deassert ready_x_out_sig
                -- TBU: Once coefficients are read, deassert ready_h_out_sig and assert ready_x_out_sig to start reading samples
                -- shift coefficients
                coefficient_mem_array(FIR_ORDER) <= h_data_in;                
                for i in FIR_ORDER-1 downto 0 loop
                    coefficient_mem_array(i) <= coefficient_mem_array(i+1);
                end loop;
            end if;
        end if;
    end process read_coefficients;

    -- read one sample at a time
    read_samples: process(clk, rst)
    begin
        if (rst = '1') then
            input_sample_mem <= ( others => '0' );
        elsif (clk'EVENT  and clk = '1') then
            if ( ready_x_out_sig = '1' and valid_x_in = '1' ) then
                -- TBU: when reading samples, deassert ready_h_out_sig
                input_sample_mem <= x_data_in;
            end if;
        end if;
    end process read_samples;

    -- Generate N parallel signed adder (registered)
    accumulate: process(clk, rst)
        variable signvec : std_logic_vector(EXTR_SIZE-1 downto 0) := ( others => '0' );
        variable tempprod : std_logic_vector(YBIT_SIZE-1 downto 0) := ( others => '0');
    begin
        if (rst = '1') then
        elsif (clk'EVENT  and clk = '1') then            
            -- N = no. of register delays or additions            
            for i in 0 to FIR_ORDER-1 loop
                -- sign extend before generating the adder
                signvec := ( others => multiplier_sigs(i)( multiplier_sigs(i)'HIGH ) );
                tempprod := signvec & multiplier_sigs(i);

                -- generate adder
                adder_mem_array(i) <= adder_mem_array(i+1) + tempprod;
            end loop;

            -- first multiplier result requires no adder and simply needs to be registered
            adder_mem_array(FIR_ORDER) <= multiplier_sigs(FIR_ORDER);
        end if;
    end process accumulate;

    -- Generate L=N+1 parallel signed multipliers (combinational)
    generate_multipliers: for i in 0 to FIR_ORDER generate 
        multiplier_sigs (i) <= coefficient_mem_array(i) * input_sample_mem;
    end generate generate_multipliers;
    
    -- handshake interface
    process(clk,rst)
    begin
        if ( rst = '1') then
            -- On reset, 
            -- 1. ready to read coefficients 
            -- 2. not ready to read input sample and produce output sample
            valid_out_sig <= '0';
            ready_h_out <= '1';
            ready_x_out <= '0';
        elsif (clk'EVENT and clk = '1') then
            if ( coeff_cnt = (FIR_ORDER-1) ) then
                -- once coefficients are read
                -- 1. disable reading coefficients 
                -- 2. ready to read input sample and produce output sample
                valid_out_sig <= '1';
                ready_h_out_sig <= '0';
                ready_x_out <= '1';
            end if;
        end if;            
    end process;

    valid_out   <= valid_out_sig;
    ready_x_out <= ready_x_out_sig;
    ready_h_out <= ready_h_out_sig;

    -- mod L=N+1 counter
    coeff_read_counter: process(clk, rst)
    begin
        if ( rst = '1') then
            coeff_cnt <= 0;
        elsif (clk'EVENT and clk = '1') then
            coeff_cnt <= coeff_cnt_next;    
        end if;
    end process coeff_read_counter;

    -- Next state logic for mod L=N+1 counter
    coeff_cnt_next <= 0 when (coeff_cnt = FIR_ORDER) else 
                             coeff_cnt + 1;

    -- mod L=N+1 counter
    --coeff_read_counter: process(clk, rst)
    --begin
    --    if ( rst = '1') then
    --        coeff_cnt <= 0;
    --    elsif (clk'EVENT and clk = '1') then
    --        if ( ready_h_out_sig = '1' and valid_h_in = '1' ) then
    --            if ( coeff_cnt = FIR_ORDER ) then
    --                coeff_cnt <= 0;
    --            else
    --                coeff_cnt <= coeff_cnt + 1;    
    --            end if;
    --        end if;
    --    end if;
    --end process coeff_read_counter

    -- output sample is registered output of last adder
    y_data_out <= adder_mem_array(0) when valid_out_sig = '1' else ( others=>'0' );
end fir_rtl_arch;
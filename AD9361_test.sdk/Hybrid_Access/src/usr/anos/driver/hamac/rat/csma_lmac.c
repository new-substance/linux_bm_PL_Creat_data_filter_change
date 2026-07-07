

// void csma_mac_set_bssid(uint8_t *bssid)
// {
// 	Write_Register(HYBRID_ACCESS_CSMA_BSSID_ADDRESS_LOW, *(uint32_t *)bssid);
// 	Write_Register(HYBRID_ACCESS_CSMA_BSSID_ADDRESS_HIGH, *(uint16_t *)(bssid + 4));
// }

// void csma_mac_set_loacal_mac_addr(uint8_t *mac_addr)
// {
// 	Write_Register(HYBRID_ACCESS_CSMA_SELF_MAC_ADDRESS_LOW, *(uint32_t *)mac_addr);
// 	Write_Register(HYBRID_ACCESS_CSMA_SELF_MAC_ADDRESS_HIGH, *(uint16_t *)(mac_addr + 4));
// }

// // ********************************************************************************************************************** //
// // ************************************************* CSMA REG CONFIG END ************************************************ //
// // ********************************************************************************************************************** //

// // static int data_num = 0;
// // static int beacon_cnt = 0;
// // static uint8_t det_data = ANOS_FALSE;
// // static last_tx_pktbuf = 0xff;
// // static uint8_t last_pkt_num = 0;
// #define TX_INTERFACE_DATA_BRAM_MASK 0x1f

// void lowmac_send_config(csma_ctl_info_t *csma_ctl_info_ptr)
// {

// 	Write_Register(TX_INTF_REG_CTS_TOSELF_CONFIG, *((uint32_t *)&(csma_ctl_info_ptr->m_cts_rts_config)));
// 	Write_Register(TX_INTF_REG_NUM_DMA_SYMBOL_TO_PL, *((uint32_t *)&(csma_ctl_info_ptr->m_num_dma_symble_to_pl)));
// 	csma_tx_interface_set_regconfig_valid(0);
// 	csma_tx_interface_set_regconfig_valid(1 << (csma_ctl_info_ptr->m_num_dma_symble_to_pl.m_queue_idx - 1));
// 	csmalmac_block_wait(1);
// 	csma_tx_interface_set_regconfig_valid(0);
// 	Write_Register(HIGH_PRIORITY_CTRL_QUEUE_DURATION, *((uint32_t *)&(csma_ctl_info_ptr->m_HighPriorityQueueENc)));
// 	csma_HighPriorityQueueENc_set_regconfig_valid(0);
// 	csma_HighPriorityQueueENc_set_regconfig_valid(1);
// 	csmalmac_block_wait(1);
// 	csma_HighPriorityQueueENc_set_regconfig_valid(0);
// }

// void rat_lowmac_hw_init()
// {
// 	/************************************************* The following is CSMA_XPU reg configeration *****************************************************/
// 	uint32_t filter_flag = 0;
// 	filter_flag = (FIF_ALLMULTI | FIF_FCSFAIL | FIF_PLCPFAIL |
// 				   FIF_BCN_PRBRESP_PROMISC | FIF_CONTROL | FIF_OTHER_BSS |
// 				   FIF_PSPOLL | FIF_PROBE_REQ | UNICAST_FOR_US |
// 				   BROADCAST_ALL_ONE | BROADCAST_ALL_ZERO | MY_BEACON |
// 				   MONITOR_ALL);

// 	csma_mac_set_short_time_band_channel(ANOS_FALSE, 44, BAND_5_8GHZ);
// 	csma_mac_set_rssi_cfg(245, 50);					   //
// 	csma_mac_set_rssi_half_bd_th(500);				   //-62db
// 	csma_mac_set_disable_use_default_time(ANOS_FALSE); // PL某些寄存器默认参数使能
// 	csma_mac_set_bb_rf_delay_count_top(49);			   //
// 	csma_mac_set_retrans_max(0);					   // 重传次数,需要csma_mac_set_need_ack(TRUE)
// 	csma_mac_set_ack_wait_top(600, 600);			   // 等待ACK最长时间(us)
// 	csma_mac_set_NAV_enable(ANOS_FALSE);			   // 低有效
// 	csma_mac_set_difs_enable(ANOS_FALSE);			   // 低有效
// 	csma_mac_set_eifs(ANOS_FALSE);					   // 低有效
// 	// csma_mac_set_cw_min(5);					//not use
// 	csma_mac_set_cts_rts_disable(ANOS_FALSE);
// 	csma_mac_set_cts_rts_rate(0x1b);
// 	csma_mac_set_duration_extra(0);
// 	csma_mac_set_rx_pkt_filter_cfg(filter_flag); // LowMAC帧过滤器
// 	csma_mac_set_loacal_mac_addr(fg_haMACAddr);
// 	csma_mac_set_bssid(fg_haMACAddr);

// 	/************************************************* The following is CSMA_HighPriorityQueueENc reg configeration *****************************************************/
// 	csma_HighPriorityQueueENc_set_queue_compete_en(0b111111);
// 	csma_HighPriorityQueueENc_set_queue_compete_en_valid(ANOS_TRUE);

// 	// SetupTxINTRPT1(); // 开启发送中断
// }

// #undef DEBUG_LOCAL_LOG_OUTPUT

/*---------------------------*\
			Include
\*---------------------------*/
#include "csma_lmac.h"

#ifdef __cplusplus
extern "C"
{
#endif // Compatible C++
#ifdef DEBUG_LOCAL_LOG_OUTPUT
#undef DEBUG_LOCAL_LOG_OUTPUT
#endif
#ifdef LOCAL_PRINTF
#undef LOCAL_PRINTF
#endif
#define DEBUG_LOCAL_LOG_OUTPUT 1
#if (DEBUG_LOCAL_LOG_OUTPUT == 1)
#define LOCAL_PRINTF LOG_PRINTF
#else
#define LOCAL_PRINTF
#endif
	/*-------------------------------------------------------*\
						  Static PV
	\*-------------------------------------------------------*/

	// 本机混合接入网卡ID
	static uint8_t fg_haMACAddr[ANOS_LOW_MAC_ADDR_MAXLEN] = ANOS_DEVICE_802_11_MAC_ADDR2; // ANOS_DEVICE_ETH1_MAC_ADDR;//

	/*-------------------------------------------------------*\
					Static fun declaration
	\*-------------------------------------------------------*/

	static anos_err_t anos_xpu_init(uint8_t f_mcs,
									uint32_t f_bb_rf_delay,
									uint32_t f_slice_count_total0,
									uint32_t f_slice_count_total1,
									uint32_t f_slice_count_start0,
									uint32_t f_slice_count_start1,
									uint32_t f_slice_count_end0,
									uint32_t f_slice_count_end1,
									uint8_t f_band,
									uint16_t f_channel,
									uint16_t f_rssi_db,
									uint8_t f_rssi_delay,
									uint16_t f_rssi_threshold,
									uint8_t f_sig_time,
									uint8_t f_ofdm_symbol_time,
									uint8_t f_slot_time,
									uint8_t f_sifs_time,
									uint8_t f_rx_start_time,
									uint16_t *f_cw_min,
									uint16_t f_ack_wait_2_4G,
									uint16_t f_ack_wait_5G,
									uint8_t f_AC1_afsi,
									uint8_t f_AC2_afsi,
									uint8_t f_AC3_afsi,
									uint8_t f_AC4_afsi,
									uint8_t f_ACHP_afsi,
									uint16_t f_ps_adjust_time,
									uint8_t f_high_allowed,
									uint32_t f_low_tsf,
									uint32_t f_tsf_high);

	static anos_err_t anos_tx_intf_init(uint16_t f_cts_to_self_wait_sifs_2_4G,
										uint16_t f_cts_to_self_wait_sifs_5G,
										uint8_t f_It_mode,
										uint16_t f_dma_symbol_to_pl);

	static anos_err_t anos_rx_intf_init(uint8_t f_max_trans_trigger,
										uint16_t f_time_out,
										uint16_t f_dma_num_to_ps);
	/*-------------------------------------------------------*\
					Static function body
	\*-------------------------------------------------------*/

	/**
	 * @brief 初始化混合接入RAT的XPU(扩展处理单元)模块
	 * @param f_mcs 调制编码方案
	 * @param f_bb_rf_delay 基带射频延迟(时钟周期)
	 * @param f_slice_count_total0 总时间片计数器0(低32位)
	 * @param f_slice_count_total1 总时间片计数器1(高32位)
	 * @param f_slice_count_start0 开始时间片计数器0(低32位)
	 * @param f_slice_count_start1 开始时间片计数器1(高32位)
	 * @param f_slice_count_end0 结束时间片计数器0(低32位)
	 * @param f_slice_count_end1 结束时间片计数器1(高32位)
	 * @param f_band 工作频段(BAND_2_4GHZ/BAND_5_8GHZ)
	 * @param f_channel 工作信道
	 * @param f_rssi_db RSSI校准值(dB)
	 * @param f_rssi_delay RSSI延迟时间
	 * @param f_rssi_threshold RSSI阈值
	 * @param f_sig_time 信号传输时间
	 * @param f_ofdm_symbol_time OFDM符号时间
	 * @param f_slot_time 时隙时间
	 * @param f_sifs_time 短帧间间隔时间
	 * @param f_rx_start_time 接收启动时间
	 * @param f_cw_min 最小竞争窗口(6个优先级队列)
	 * @param f_ack_wait_2_4G 2.4G频段ACK等待超时(us)
	 * @param f_ack_wait_5G 5G频段ACK等待超时(us)
	 * @param f_AC1_afsi AC1仲裁帧间间隔
	 * @param f_AC2_afsi AC2仲裁帧间间隔
	 * @param f_AC3_afsi AC3仲裁帧间间隔
	 * @param f_AC4_afsi AC4仲裁帧间间隔
	 * @param f_ACHP_afsi ACHP(高优先级)仲裁帧间间隔
	 * @param f_ps_adjust_time PS(节能)模式调整时间
	 * @param f_high_allowed 允许的高优先级传输标志
	 * @param f_low_tsf TSF时间戳低32位
	 * @param f_tsf_high TSF时间戳高32位
	 * @return anos_err_t 初始化状态
	 * @note RX 过滤器采用 3级层次化架构 (filter.v): 初始化时直接配置默认过滤规则
	 *       - RX SELF_MAC 判定由 PL 硬件连线 self_mac_addr 自动完成
	 *       - ANOS_RAT_Cfg_MAC_Addr() 配置 TX 端 MAC 地址 (TX 帧头 TA/SA 字段)
	 *       其他: 物理层时序 (CSMA/CA), QoS (CW+AIFS), RSSI, TSF
	 */
	static anos_err_t anos_xpu_init(uint8_t f_mcs,
									uint32_t f_bb_rf_delay,
									uint32_t f_slice_count_total0,
									uint32_t f_slice_count_total1,
									uint32_t f_slice_count_start0,
									uint32_t f_slice_count_start1,
									uint32_t f_slice_count_end0,
									uint32_t f_slice_count_end1,
									uint8_t f_band,
									uint16_t f_channel,
									uint16_t f_rssi_db,
									uint8_t f_rssi_delay,
									uint16_t f_rssi_threshold,
									uint8_t f_sig_time,
									uint8_t f_ofdm_symbol_time,
									uint8_t f_slot_time,
									uint8_t f_sifs_time,
									uint8_t f_rx_start_time,
									uint16_t *f_cw_min,
									uint16_t f_ack_wait_2_4G,
									uint16_t f_ack_wait_5G,
									uint8_t f_AC1_afsi,
									uint8_t f_AC2_afsi,
									uint8_t f_AC3_afsi,
									uint8_t f_AC4_afsi,
									uint8_t f_ACHP_afsi,
									uint16_t f_ps_adjust_time,
									uint8_t f_high_allowed,
									uint32_t f_low_tsf,
									uint32_t f_tsf_high)
	{

		// [GEMINI_UPDATE]: Multi reset sequence matching Linux driver
		int i;
		for (i = 0; i < 32; i++)
		{
			ANOS_RAT_XPU_Soft_Do_Reset();
		}
		ANOS_RAT_XPU_Soft_Undo_Reset();

		uint8_t ix;
		uint32_t reg_value;

		// 收端过滤器: 3级层次化架构 (filter.v), 初始化时直接配置默认过滤规则
		ANOS_RAT_Cfg_Filter_Default();

		ANOS_RAT_Cfg_CTS_To_RTS(f_mcs);

		ANOS_RAT_Cfg_BB_RF_Delay(f_bb_rf_delay);

		ANOS_RAT_Cfg_MAC_Addr(fg_haMACAddr);  // TX 发送端 MAC 地址 (非 RX 过滤)

		ANOS_RAT_Cfg_MAX_Retrans_Num(0);

		// [GEMINI_DELETE]: Obsolete SLICE_COUNT initialization removed

		// 配置频带和 channel
		ANOS_RAT_Cfg_Band(f_band);

		ANOS_RAT_Cfg_Channel(f_channel);

		ANOS_RAT_Erp_Short_Slot_Disable();

		// 配置 RSSI
		ANOS_RAT_Cfg_RSSI_dB(f_rssi_db);

		ANOS_RAT_Cfg_RSSI_Delay(f_rssi_delay);

		ANOS_RAT_Cfg_RSSI_Threshold(f_rssi_threshold);

		ANOS_RAT_RSSI_FIFO_Delay_Do_Reset();

		ANOS_RAT_RSSI_FIFO_Delay_Undo_Reset();

		// 配置 CSMA Time Debug
		ANOS_RAT_Cfg_Time_Debug(e_debug_sig_time, f_sig_time);

		ANOS_RAT_Cfg_Time_Debug(e_debug_ofdm_symbol_time, f_ofdm_symbol_time);

		ANOS_RAT_Cfg_Time_Debug(e_debug_slot_time, f_slot_time);

		ANOS_RAT_Cfg_Time_Debug(e_debug_sifs_time, f_sifs_time);

		ANOS_RAT_Cfg_Time_Debug(e_debug_rx_start_time, f_rx_start_time);

		reg_value = rat_read_reg(CREG_HA_RAT_XPU_REG_CSMA_TIME_DEBUG);
		LOCAL_PRINTF("CREG_HA_RAT_XPU_REG_CSMA_TIME_DEBUG value is %u\n\r", reg_value);

		// 配置 CW Min
		for (ix = 0; ix < 6; ix++)
		{
			ANOS_RAT_Cfg_CW_Min(f_cw_min[ix], ix + 1);
		}

		// 开启 NAV / DIFS / EIFS
		ANOS_RAT_Cfg_NAV_Enable();
		ANOS_RAT_Cfg_DIFS_Enable();
		ANOS_RAT_Cfg_EIFS_Enable();

		// 配置 ACK 最大等待时间
		ANOS_RAT_Cfg_ACK_Wait_Top(f_ack_wait_2_4G, f_ack_wait_5G);
		reg_value = rat_read_reg(CREG_HA_RAT_XPU_REG_SEND_ACK_WAIT_TOP);
		LOCAL_PRINTF("CREG_HA_RAT_XPU_REG_SEND_ACK_WAIT_TOP value is %u\n\r", reg_value);

		// 配置 AIFS
		ANOS_RAT_Cfg_AIFS_ACx(f_AC1_afsi, e_AC1);
		ANOS_RAT_Cfg_AIFS_ACx(f_AC2_afsi, e_AC2);
		ANOS_RAT_Cfg_AIFS_ACx(f_AC3_afsi, e_AC3);
		ANOS_RAT_Cfg_AIFS_ACx(f_AC4_afsi, e_AC4);
		ANOS_RAT_Cfg_AIFS_ACx(f_ACHP_afsi, e_ACHP);

		ANOS_RAT_Cfg_PS_Adjust_Time(f_ps_adjust_time);

		// 配置 high_allowed
		ANOS_RAT_Cfg_Tx_High_Allowed_SW(f_high_allowed);

		// 配置 TSF load
		ANOS_RAT_Cfg_TSF_Load_Value(f_low_tsf, f_tsf_high);

		// [GEMINI_UPDATE]: Updated debug prints to match single CW_MIN register
		reg_value = rat_read_reg(CREG_HA_RAT_XPU_REG_CW_MIN_ADDR);
		LOCAL_PRINTF("CREG_HA_RAT_XPU_REG_CW_MIN_ADDR value is %u\n\r", reg_value);

		return ANOS_EOK;
	}

	/**
	 * @brief 初始化混合接入RAT的发送接口
	 * @param f_cts_to_self_wait_sifs_2_4G 2.4G频段CTS-to-Self等待SIFS时间
	 * @param f_cts_to_self_wait_sifs_5G 5G频段CTS-to-Self等待SIFS时间
	 * @param f_It_mode 中断模式
	 * @param f_dma_symbol_to_pl DMA传输到物理层的符号数
	 * @return anos_err_t 初始化状态
	 * @note 发送接口配置:
	 *       - CTS-to-Self机制参数(避免隐藏节点问题)
	 *       - 中断模式(控制硬件事件通知方式)
	 *       - DMA传输参数(影响发送效率)
	 *       函数包含硬件复位序列保证可靠初始化
	 */
	static anos_err_t anos_tx_intf_init(uint16_t f_cts_to_self_wait_sifs_2_4G,
										uint16_t f_cts_to_self_wait_sifs_5G,
										uint8_t f_It_mode,
										uint16_t f_dma_symbol_to_pl)
	{
		int i;
		// [GEMINI_UPDATE]: Multi reset sequence matching Linux driver
		for (i = 0; i < 32; i++)
		{
			ANOS_RAT_Tx_Do_Reset();
		}
		ANOS_RAT_Tx_Undo_Reset();

		// [GEMINI_UPDATE]: Initializing new Tx registers with defaults matching Linux side config
		ANOS_RAT_Tx_Cfg_Mixer_Cfg(0x200202F6); // Default mixer for 20MHz
		ANOS_RAT_Tx_Cfg_Wifi_Tx_Mode(0);
		ANOS_RAT_Tx_Cfg_IQ_Src_Sel(0);
		ANOS_RAT_Tx_Cfg_Misc_Sel(1); // ant_sel = 1
		ANOS_RAT_Tx_Cfg_BB_Gain(0);
		ANOS_RAT_Tx_Cfg_Hold_Threshold(0x80);
		ANOS_RAT_Tx_Cfg_Start_Trans_To_Ps_Mode(2);
		ANOS_RAT_Tx_Cfg_Cfg_Data_To_Ant(0);

		// 配置 CTS to Self
		ANOS_RAT_Tx_Cfg_CTS_To_Self_Wait_SIFS_2_4G(f_cts_to_self_wait_sifs_2_4G);

		ANOS_RAT_Tx_Cfg_CTS_To_Self_Wait_SIFS_5G(f_cts_to_self_wait_sifs_5G);

		// 配置 Tx 中断
		ANOS_RAT_Interrupt0_Enable();

		ANOS_RAT_Interrupt1_Enable();

		ANOS_RAT_Cfg_Interrupt_Mode(f_It_mode);

		// [GEMINI_DELETE]: Obsolete DMA Symbol configuration removed

		return ANOS_EOK;
	}

	/**
	 * @brief 初始化混合接入RAT的接收接口
	 * @param f_max_trans_trigger 最大传输触发次数
	 * @param f_time_out 接收超时时间
	 * @param f_dma_num_to_ps DMA到协议栈的包数量
	 * @return anos_err_t 初始化状态
	 * @note 接收接口配置:
	 *       - 自动恢复机制(错误处理)
	 *       - 接收超时时间(防止DMA挂起)
	 *       - 监控模式配置
	 *       - DMA传输参数(影响接收效率)
	 *       函数包含硬件复位序列保证可靠初始化
	 */
	static anos_err_t anos_rx_intf_init(uint8_t f_max_trans_trigger,
										uint16_t f_time_out,
										uint16_t f_dma_num_to_ps)
	{
		int i;

		ANOS_RAT_Rx_Auto_Recover_Enable();

		ANOS_RAT_Rx_Cfg_M_Tlast_Timeout(f_time_out);

		// [GEMINI_UPDATE]: Set Auto Reset Wait Time
		ANOS_RAT_Rx_Cfg_Auto_Rst_Wait_Time(7000);

		// [GEMINI_UPDATE]: Multi reset sequence matching Linux driver
		for (i = 0; i < 32; i++)
		{
			ANOS_RAT_Rx_Do_Reset();
		}
		ANOS_RAT_Rx_Undo_Reset();

		// [GEMINI_UPDATE]: Set M_AXIS Reset matching Linux logic
		ANOS_RAT_Rx_Cfg_M_Axis_Rst(1);

		// 配置 收端模式
		ANOS_RAT_Rx_Endless_Mode_Disable();

		ANOS_RAT_Rx_Monitor_DMA_Symbol_Mode_Enable();

		ANOS_RAT_Rx_Cfg_Max_Trans_Trigger(f_max_trans_trigger);

		ANOS_RAT_Rx_Start_1_Trans_Ext_Trigger_Disable();

		ANOS_RAT_Rx_Ps_Src_Disable();

		// [GEMINI_DELETE]: Obsolete DMA Num To Ps configuration removed

		return ANOS_EOK;
	}
	/*-------------------------------------------------------*\
					Extern function body
	\*-------------------------------------------------------*/

	/**
	 * @brief 混合接入RAT的低MAC层整体初始化
	 * @return anos_err_t 初始化状态
	 * @note 三阶段初始化:
	 *       1. XPU核心 (anos_xpu_init): 过滤器直接配置为默认规则
	 *       2. 发送接口 (anos_tx_intf_init)
	 *       3. 接收接口 (anos_rx_intf_init)
	 *       参数: 5.8GHz 频段, 信道44, MCS 11 (OFDM 54Mbps), RSSI阈值-62dBm
	 */
	anos_err_t ANOS_HA_RAT_Init(void)
	{
		anos_err_t r;
		uint16_t cw_min[6] = {5, 4, 3, 2, 2, 0};

		r = anos_xpu_init(0xB,		   // f_mcs
						  (49),		   // f_bb_rf_delay
						  (50000 - 1), // f_slice_count_total0
						  (50000 - 1), // f_slice_count_total1
						  (0),		   // f_slice_count_start0
						  (49000),	   // f_slice_count_start1
						  (50000 - 1), // f_slice_count_end0
						  (50000 - 1), // f_slice_count_end1
						  BAND_5_8GHZ, // f_band
						  (44),		   // f_channel
						  (245),	   // f_rssi_db
						  (50),		   // f_rssi_delay
						  (500),	   // f_rssi_threshold
						  (20),		   // f_sig_time
						  (4),		   // f_ofdm_symbol_time
						  (3),		   // f_slot_time
						  (10),		   // f_sifs_time
						  (5),		   // f_rx_start_time
						  cw_min,	   // f_cw_min  1 ~ 6 {5, 4, 3, 2, 2, 0}
						  (1200),	   // f_ack_wait_2_4G
						  (1200),	   // f_ack_wait_5G
						  (2),		   // f_AC1_afsi
						  (2),		   // f_AC2_afsi
						  (3),		   // f_AC3_afsi
						  (3),		   // f_AC4_afsi
						  (5),		   // f_ACHP_afsi
						  (11),		   // f_ps_adjust_time
						  (0x3f),	   // f_high_allowed
						  0,		   // f_low_tsf
						  0			   // f_tsf_high
		);

		if (r != ANOS_EOK)
		{
			ULOG_ERROR(" RAT XPU Init failed in ANOS_HA_RAT_Init !\n\r");
			return ANOS_ERROR;
		}

		r = anos_tx_intf_init((10 * 10),
							  (16 * 10),
							  (40),
							  (8));

		if (r != ANOS_EOK)
		{
			ULOG_ERROR(" RAT Tx_intf Init failed in ANOS_HA_RAT_Init !\n\r");
			return ANOS_ERROR;
		}

		r = anos_rx_intf_init((0x10025),
							  (7000),
							  (8));

		if (r != ANOS_EOK)
		{
			ULOG_ERROR(" RAT Rx_intf Init failed in ANOS_HA_RAT_Init !\n\r");
			return ANOS_ERROR;
		}

		return ANOS_EOK;
	}

	/**
	 * @brief 通知 PL 端 PS 未就绪, 屏蔽所有 Rx 帧
	 * @note 调用 ANOS_RAT_Cfg_Filter_BlockAll():
	 *       L0=0 → 无分类使能, l0_match 恒为0 → 所有帧在 L0 被丢弃
	 *       用于系统初始化阶段和 PS 不可用时, 防止 PL 端 DMA 收到未处理的帧
	 */
	void ANOS_HA_Ps_Is_Not_Ready(void)
	{
		ANOS_RAT_Cfg_Filter_BlockAll();
	}

	/**
	 * @brief 通知 PL 端 PS 已就绪, 启用默认 Rx 过滤器
	 * @note 调用 ANOS_RAT_Cfg_Filter_Default():
	 *       L0: EN_CTRL|EN_DATA|EN_MANAGE
	 *       L1: CTRL PS_POLL | DATA BROADCAST/MULTICAST/SELF_MAC
	 *            | MANAGE BEACON/DETECT_REQ/DETECT_REP
	 *       L2: THIS_LDC=1 透传 (不做地址过滤)
	 *       SELF_MAC 判定由 PL 硬件连线 self_mac_addr 自动完成
	 */
	void ANOS_HA_Ps_Is_Ready(void)
	{
		ANOS_RAT_Cfg_Filter_Default();
	}

#ifdef __cplusplus
}
#endif // Compatible C++

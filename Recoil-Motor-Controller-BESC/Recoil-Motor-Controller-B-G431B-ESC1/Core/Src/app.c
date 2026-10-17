/*
 * app.c
 *
 *  Created on: Aug 24, 2022
 *      Author: TK
 */


#include "app.h"

extern ADC_HandleTypeDef hadc1;
extern ADC_HandleTypeDef hadc2;
extern FDCAN_HandleTypeDef hfdcan1;
extern I2C_HandleTypeDef hi2c1;
extern OPAMP_HandleTypeDef hopamp1;
extern OPAMP_HandleTypeDef hopamp2;
extern OPAMP_HandleTypeDef hopamp3;
extern TIM_HandleTypeDef htim1;
extern TIM_HandleTypeDef htim2;
extern TIM_HandleTypeDef htim6;
extern TIM_HandleTypeDef htim8;
extern UART_HandleTypeDef huart2;

MotorController controller;

void HAL_FDCAN_RxFifo0Callback(FDCAN_HandleTypeDef *hfdcan, uint32_t RxFifo0ITs) {
  // Drain the whole FIFO (local fix, 2026-10-13). Upstream read one frame per interrupt; after a
  // burst of bus errors the FIFO kept a backlog of 2, so every request was answered with the frame
  // received two requests earlier (seen on the bench as "ESC receives pings but never replies").
  while (HAL_FDCAN_GetRxFifoFillLevel(&hfdcan1, FDCAN_RX_FIFO0) > 0) {
    CAN_Frame rx_frame;
    CAN_getRxFrame(&hfdcan1, &rx_frame);
    MotorController_handleCANMessage(&controller, &rx_frame);
  }
}

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim) {
  if (htim == &htim1) {
    MotorController_update(&controller);
    /* ====== Start user APP code ====== */
    //  controller.position_controller.position_target = APP_getUserPot() * M_PI;

    /* ====== End user APP code ====== */
  }
  else if (htim == &htim2) {
    #if SAFETY_WATCHDOG_ENABLED
    // watchdog time: 1000ms
    if (controller.mode != MODE_DISABLED && controller.mode != MODE_IDLE && controller.mode != MODE_CALIBRATION) {
      MotorController_setMode(&controller, MODE_DAMPING);
      SET_BITS(controller.error, ERROR_WATCHDOG_TIMEOUT);
    }
    #endif
  }
  else if (htim == &htim8) {
    if (controller.fast_frame_frequency != 0) {
      CAN_Frame tx_frame;
      tx_frame.id = (FUNC_TRANSMIT_PDO_4 << 7) | controller.device_id;
      tx_frame.id_type = CAN_ID_STANDARD;
      tx_frame.frame_type = CAN_FRAME_DATA;
      tx_frame.size = 8;
      *((float *)tx_frame.data + 0) = PositionController_getPositionMeasured(&controller.position_controller);
      *((float *)tx_frame.data + 1) = PositionController_getVelocityMeasured(&controller.position_controller);
      if (HAL_FDCAN_GetTxFifoFreeLevel(&hfdcan1) >= 2) {
        CAN_putTxFrame(&hfdcan1, &tx_frame);
      }
    }
  }
}

void HAL_I2C_MasterRxCpltCallback(I2C_HandleTypeDef *hi2c) {
  // do nothing here
}

/**
 * Procedure following G431 User Manual Section 4.4.2 Option bytes programming
 *
 */
void APP_initFlashOption() {
  // 1. Unlock the FLASH_CR with the LOCK clearing sequence
  // Check that no Flash memory operation is on going by checking the BSY bit in the Flash status register (FLASH_SR).
  while (__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)) {}
  HAL_FLASH_Unlock();

  // 2. Unlock the FLASH Option Byte with the LOCK clearing sequence
  // Check that no Flash memory operation is on going by checking the BSY bit in the Flash status register (FLASH_SR).
  while (__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)) {}
  HAL_FLASH_OB_Unlock();

  // 3. program OPTR
  FLASH->OPTR = 0xFBEFF8AAU;  // default to boot from flash

  // 4. Set the Options Start bit OPTSTRT in the Flash control register (FLASH_CR).
  SET_BITS(FLASH->CR, FLASH_CR_OPTSTRT);

  // 4.1 clear status register
  SET_BITS(FLASH->SR, FLASH_SR_OPTVERR | FLASH_SR_RDERR);

  // 5. Wait for the BSY bit to be cleared.
  while (__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY)) {}

  // 6. Lock Flash
  // If LOCK is set by software, OPTLOCK is automatically set too
  HAL_FLASH_Lock();

  // 7. reload the new settings
  // seems this line will cause error when put before FLASH_Lock(), which will then corrupt all Flash settings
  // so putting it here
  // can also comment out this line and just power cycle to update the flash settings
  HAL_FLASH_OB_Launch();
}

#if DEMO_STANDALONE
/*
 * Encoder bring-up aid: Encoder_init() blocks until the AS5600 answers, so scan the I2C1 bus
 * (PB7 SDA, PB8 SCL) once before it and leave the result in RAM for SWD:
 *   i2c_scan_found[0..n]   addresses that ACKed (n = i2c_scan_count), i2c_scan_error = HAL error of 0x36
 *   i2c_scan_done          0x5CA4DONE when finished
 */
volatile uint32_t i2c_scan_done = 0;
volatile uint32_t i2c_scan_count = 0;
volatile uint32_t i2c_scan_error = 0;
volatile uint8_t i2c_scan_found[16];

static void APP_i2cScan() {
  HAL_I2C_Init(&hi2c1);
  HAL_Delay(100);
  for (uint16_t addr = 0x08; addr < 0x78; addr += 1) {
    if (HAL_I2C_IsDeviceReady(&hi2c1, addr << 1, 2, 5) == HAL_OK && i2c_scan_count < sizeof(i2c_scan_found)) {
      i2c_scan_found[i2c_scan_count++] = (uint8_t)addr;
    }
  }
  uint8_t buf[2];
  if (HAL_I2C_Mem_Read(&hi2c1, AS5600_I2C_ADDR << 1, AS5600_ANGLE_ADDR, I2C_MEMADD_SIZE_8BIT, buf, 2, 100) != HAL_OK) {
    i2c_scan_error = HAL_I2C_GetError(&hi2c1) | 0x80000000U;
  }
  i2c_scan_done = 0x5CA4D0E5U;
}
#endif

void APP_init() {
  #if FIRST_TIME_BOOTUP
    APP_initFlashOption();
    MotorController_storeConfig(&controller);
    while (1) {}
  #endif

  #if DEMO_STANDALONE
    APP_i2cScan();
  #endif

  // On-board 120 ohm CAN terminator (analog switch on PC14). main.c drives the pin LOW (= off);
  // on the 2-node bench bus (adapter + this ESC) that gave Bit1 errors and bus-off, HIGH gave none.
  HAL_GPIO_WritePin(GPIO_CAN_TERM_GPIO_Port, GPIO_CAN_TERM_Pin,
                    CAN_TERMINATION_ENABLED ? GPIO_PIN_SET : GPIO_PIN_RESET);

  MotorController_init(&controller);


//  HAL_Delay(1000);
//
//  controller.position_controller.gear_ratio = 1.f;
//  controller.position_controller.torque_limit = 1.f;
//  MotorController_setMode(&controller, MODE_TORQUE);

}

uint8_t APP_getUserButton() {
  return HAL_GPIO_ReadPin(GPIO_BUTTON_GPIO_Port, GPIO_BUTTON_Pin) ? 0 : 1;
}

float APP_getUserPot() {
  return HAL_ADCEx_InjectedGetValue(&hadc1, ADC_INJECTED_RANK_3) * ADC_READING_COEFFICIENT / 3.3;
}


#if DEMO_STANDALONE
/*
 * Standalone demo: button -> calibration -> button -> sine in MODE_POSITION -> button -> stop.
 * Units are motor side (gear_ratio stays 1): 15 motor rad = 1 output rad on the 15:1 reducer.
 * Gains are conservative starting values, not tuned on hardware.
 */
#define DEMO_AMPLITUDE      4.5f      // motor rad (= 0.3 rad at the output)
#define DEMO_FREQUENCY      0.25f     // Hz
#define DEMO_RAMP_MS        2000.f    // amplitude fade-in
#define DEMO_KP             0.5f      // N*m / motor rad
#define DEMO_KD             0.01f     // N*m / (motor rad/s)
#define DEMO_TORQUE_LIMIT   0.3f      // N*m motor side (~2.6 A with Kt 0.1176, below the 3 A calibration current)
#define DEMO_ERROR_LIMIT    1.5f      // motor rad of tracking error -> DAMPING
#define DEMO_MIN_BUS_V      9.f

static uint8_t demo_state = 0;        // 0 wait, 1 calibrated/idle, 2 running
static uint8_t demo_button_prev = 0;
volatile uint32_t demo_remote_press = 0;   // written over SWD (non-zero = one button press), cleared by the demo
static uint32_t demo_t0 = 0;
static float demo_p0 = 0.f;

__attribute__((unused)) static void APP_demoStep() {
  uint8_t button = APP_getUserButton();
  uint8_t pressed = (button && !demo_button_prev) || demo_remote_press;
  demo_remote_press = 0;
  demo_button_prev = button;

  if (demo_state == 0) {
    if (pressed && controller.powerstage.bus_voltage_measured > DEMO_MIN_BUS_V) {
      MotorController_setMode(&controller, MODE_CALIBRATION);   // runs in updateService, blocks ~10 s
      demo_state = 1;
    }
  }
  else if (demo_state == 1) {
    if (pressed && controller.mode == MODE_IDLE && controller.error == 0) {
      controller.position_controller.position_kp = DEMO_KP;
      controller.position_controller.velocity_kp = DEMO_KD;
      controller.position_controller.torque_limit = DEMO_TORQUE_LIMIT;
      controller.position_controller.torque_target = 0.f;
      demo_p0 = controller.position_controller.position_measured;
      controller.position_controller.position_target = demo_p0;
      demo_t0 = HAL_GetTick();
      MotorController_setMode(&controller, MODE_POSITION);
      demo_state = 2;
    }
  }
  else {
    float t_ms = (float)(HAL_GetTick() - demo_t0);
    float ramp = t_ms < DEMO_RAMP_MS ? t_ms / DEMO_RAMP_MS : 1.f;
    float target = demo_p0 + ramp * DEMO_AMPLITUDE * sinf(2.f * M_PI_F * DEMO_FREQUENCY * t_ms * 0.001f);
    controller.position_controller.position_target = target;

    float error = target - controller.position_controller.position_measured;
    if (pressed || controller.mode != MODE_POSITION || error > DEMO_ERROR_LIMIT || error < -DEMO_ERROR_LIMIT) {
      MotorController_setMode(&controller, MODE_DAMPING);
      HAL_Delay(500);
      MotorController_setMode(&controller, MODE_IDLE);
      demo_state = 1;
    }
  }

  // the demo has no CAN host to feed the safety watchdog; feed it from this loop instead,
  // so a hung main loop still ends in DAMPING
  __HAL_TIM_SET_COUNTER(&htim2, 0);
}

#if OPENLOOP_NO_ENCODER
/*
 * Open-loop demo (no encoder, no CAN): button -> voltage vector follows a slow sine -> button -> stop.
 * The rotor follows the field like a stepper; nothing is measured, so keep the load small.
 */
#define DEMO_OL_VOLTAGE     1.0f      // V amplitude (~1.6 A at standstill)

static void APP_demoStepOpenLoop() {
  uint8_t button = APP_getUserButton();
  uint8_t pressed = (button && !demo_button_prev) || demo_remote_press;
  demo_remote_press = 0;
  demo_button_prev = button;

  if (demo_state != 2) {
    if (pressed && controller.mode == MODE_IDLE
        && controller.powerstage.bus_voltage_measured > DEMO_MIN_BUS_V) {
      MotorController_setOpenLoopCommand(&controller, 0.f, 0.f);
      MotorController_setMode(&controller, MODE_VALPHABETA_OVERRIDE);
      demo_t0 = HAL_GetTick();
      demo_state = 2;
    }
  }
  else {
    float t_ms = (float)(HAL_GetTick() - demo_t0);
    float ramp = t_ms < DEMO_RAMP_MS ? t_ms / DEMO_RAMP_MS : 1.f;
    float target = ramp * DEMO_AMPLITUDE * sinf(2.f * M_PI_F * DEMO_FREQUENCY * t_ms * 0.001f);
    // the voltage also ramps in, so the rotor snaps gently onto the first field direction
    MotorController_setOpenLoopCommand(&controller, target, ramp * DEMO_OL_VOLTAGE);

    if (pressed || controller.mode != MODE_VALPHABETA_OVERRIDE) {
      MotorController_setMode(&controller, MODE_DAMPING);
      HAL_Delay(500);
      MotorController_setMode(&controller, MODE_IDLE);
      demo_state = 0;
    }
    // feed the watchdog only while the button demo drives the motor; when a CAN host drives it,
    // the host's RPDO3 frames feed it, so a lost host still ends in DAMPING
    __HAL_TIM_SET_COUNTER(&htim2, 0);
  }
}
#endif
#endif

void APP_main() {
  MotorController_updateService(&controller);

#if DEMO_STANDALONE
  #if OPENLOOP_NO_ENCODER
    APP_demoStepOpenLoop();
  #else
    APP_demoStep();
  #endif
  HAL_Delay(5);
  return;
#endif

//  if (APP_getUserButton()) {
//    MotorController_setMode(&controller, MODE_CALIBRATION);
//  }


//  controller.current_controller.i_q_target = 5 * APP_getUserPot();
//  controller.position_controller.torque_target = -1 * APP_getUserPot();
//  controller.position_controller.position_target = 20 * APP_getUserPot();


//  char str[128];

//  sprintf(str, "i_tar:%f,i_meas:%f,i_set:%f\r\n",
//      controller.current_controller.i_q_target,
//      controller.current_controller.i_q_measured,
//      controller.current_controller.i_q_setpoint);

//  sprintf(str, "vel_tar:%f,vel_meas:%f,torque:%f\r\n",
//      controller.position_controller.velocity_target,
//      controller.position_controller.velocity_measured,
//      controller.position_controller.torque_setpoint);

//  sprintf(str, "pos_tar:%f,pos_meas:%f,vel_meas:%f,torque:%f,iq:%f\r\n",
//      controller.position_controller.position_target,
//      controller.position_controller.position_measured,
//      controller.position_controller.velocity_measured,
//      controller.position_controller.torque_setpoint,
//      controller.current_controller.i_q_setpoint);

//  HAL_UART_Transmit(&huart2, (uint8_t *)str, strlen(str), 1000);

  HAL_Delay(50);
}


using UnityEngine;

public class Screenshot : MonoBehaviour{
    void Update(){
        if (Input.GetKeyDown(KeyCode.K)) {
            ScreenCapture.CaptureScreenshot("WaterWithFFT_HighResScreenshot.png", 2);
        }
    }
}

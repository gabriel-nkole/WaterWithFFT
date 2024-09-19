using UnityEngine;

public struct CascadeParams {
    // Texture Parameters
    public int Resolution;

    public int M;


    // Wind Parameters
    public float Gravity;

    public float WindSpeed;

    public float L_;

    public Vector2 WindDirection;

    public int DirectionExpOver2;

    public float Amplitude;

    public float smallL;


    // Displacement Parameters
    public float lambda;


    // Foam
    public float FoamBias;

    public float decayFactor;

    public Color FoamColor;


    // Thread Info
    public int LOCAL_WORK_GROUPS_X;
    public int threadGroupsX;
    public int threadGroupsY;


    // Ocean Material
    public Material OceanMaterial;
};


public class Cascade {
    // Input Parameters
    private int ID;
    private int L;
    private int L0;
    private CascadeParams cascParams;

    private Texture2D noise;
    private RenderTexture butterfly;


    // Compute Shaders
    private ComputeShader InitialSpectrum_CS = Object.Instantiate(Resources.Load<ComputeShader>("InitialSpectrum"));
    private ComputeShader Spectrum_CS = Object.Instantiate(Resources.Load<ComputeShader>("Spectrum"));
    private ComputeShader Butterflies_CS = Object.Instantiate(Resources.Load<ComputeShader>("Butterflies"));
    private ComputeShader Normalise_CS = Object.Instantiate(Resources.Load<ComputeShader>("Normalise"));
    private ComputeShader Foam_CS = Object.Instantiate(Resources.Load<ComputeShader>("Foam"));

    
    // Textures
    private RenderTexture h0k;
    private RenderTexture h0minusk;

    private RenderTexture X_Y_Z_dXdx;
    private RenderTexture dYdx_dYdz_dZdx_dZdz;

    private RenderTexture pingpong0;
    private RenderTexture pingpong1;

    private RenderTexture Displacement;
    private RenderTexture Slope;
    private RenderTexture Foam;


    public Cascade(int inID, int inL, int inL0, CascadeParams inCascParams, Texture2D inNoise, RenderTexture inButterfly) {
        ID = inID;
        L = inL;
        L0 = inL0;
        cascParams = inCascParams;

        noise = inNoise;
        butterfly = inButterfly;
    }


    public void OnEnable() {
        // Texture Allocation
        h0k = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat, false, RenderTextureFormat.RGFloat);
        h0minusk = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat, false, RenderTextureFormat.RGFloat);

        X_Y_Z_dXdx = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat);
        dYdx_dYdz_dZdx_dZdz = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat);

        pingpong0 = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat);
        pingpong1 = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat);

        Displacement = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat);
        Slope = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat, true);
        Foam = CreateRenderTexture(cascParams.M, FilterMode.Trilinear, TextureWrapMode.Repeat, true);


        
        // Initial Spectrum
        InitialSpectrum_CS.SetFloat("M", cascParams.M);
        InitialSpectrum_CS.SetFloat("L", L);

        InitialSpectrum_CS.SetFloat("g", cascParams.Gravity);
        InitialSpectrum_CS.SetFloat("V", cascParams.WindSpeed);
        InitialSpectrum_CS.SetFloat("L_", cascParams.L_);
        InitialSpectrum_CS.SetVector("windDirection", cascParams.WindDirection);
        InitialSpectrum_CS.SetInt("directionExp", cascParams.DirectionExpOver2 * 2);
        InitialSpectrum_CS.SetFloat("A", cascParams.Amplitude);
        InitialSpectrum_CS.SetFloat("l", cascParams.smallL);

        InitialSpectrum_CS.SetTexture(0, "noise", noise);
        InitialSpectrum_CS.SetTexture(0, "h0k", h0k);
        InitialSpectrum_CS.SetTexture(0, "h0minusk", h0minusk);
        InitialSpectrum_CS.Dispatch(0, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);


        // Spectrum (setup)
        Spectrum_CS.SetFloat("M", cascParams.M);
        Spectrum_CS.SetFloat("L", L);
        Spectrum_CS.SetFloat("g", cascParams.Gravity);
        Spectrum_CS.SetTexture(0, "h0k", h0k);
        Spectrum_CS.SetTexture(0, "h0minusk", h0minusk);
        Spectrum_CS.SetTexture(0, "X_Y_Z_dXdx", X_Y_Z_dXdx);
        Spectrum_CS.SetTexture(0, "dYdx_dYdz_dZdx_dZdz", dYdx_dYdz_dZdx_dZdz);


        // Butterflies (setup)
        Butterflies_CS.SetFloat("M", cascParams.M);
        Butterflies_CS.SetTexture(0, "butterfly", butterfly);
        Butterflies_CS.SetTexture(0, "pingpong0", pingpong0);
        Butterflies_CS.SetTexture(0, "pingpong1", pingpong1);

        Butterflies_CS.SetTexture(1, "butterfly", butterfly);
        Butterflies_CS.SetTexture(1, "pingpong0", pingpong0);
        Butterflies_CS.SetTexture(1, "pingpong1", pingpong1);


        // Normalise (setup)
        Normalise_CS.SetFloat("M", cascParams.M);
        Normalise_CS.SetFloat("lambda", cascParams.lambda);
        Normalise_CS.SetTexture(0, "X_Y_Z_dXdx", X_Y_Z_dXdx);
        Normalise_CS.SetTexture(0, "dYdx_dYdz_dZdx_dZdz", dYdx_dYdz_dZdx_dZdz);
        Normalise_CS.SetTexture(0, "Displacement", Displacement);
        Normalise_CS.SetTexture(0, "Slope", Slope);


        // Foam (setup)
        Foam_CS.SetTexture(0, "Displacement", Displacement);
        Foam_CS.SetTexture(0, "Slope", Slope);
        Foam_CS.SetTexture(0, "Foam", Foam);
        Foam_CS.SetFloat("M", cascParams.M);
        Foam_CS.SetFloat("lambda", cascParams.lambda);
        Foam_CS.SetFloat("FoamBias", cascParams.FoamBias);
        Foam_CS.SetVector("FoamColor", cascParams.FoamColor);
        Foam_CS.SetFloat("decayFactor", cascParams.decayFactor);

        Foam_CS.SetFloat("L0divL", (float)L0/(float)L);



        // Sending to Ocean Material
        cascParams.OceanMaterial.SetFloat("A", cascParams.Amplitude);
        
        cascParams.OceanMaterial.SetFloat($"L{ID}", L);
        cascParams.OceanMaterial.SetTexture($"Displacement{ID}", Displacement);
        cascParams.OceanMaterial.SetTexture($"Slope{ID}", Slope);
        cascParams.OceanMaterial.SetTexture($"Foam{ID}", Foam);
    }

    public void OnDisable() {
        //Not sure if this needs to be freed, but freeing just in-case
        Object.Destroy(noise);
        butterfly.Release();

        noise = null;
        butterfly = null;


        // Free Compute Shaders
        Object.Destroy(InitialSpectrum_CS);
        Object.Destroy(Spectrum_CS);
        Object.Destroy(Butterflies_CS);
        Object.Destroy(Normalise_CS);
        Object.Destroy(Foam);

        InitialSpectrum_CS = null;
        Spectrum_CS = null;
        Butterflies_CS = null;
        Normalise_CS = null;
        Foam_CS = null;


        // Free Render Textures
        h0k.Release();
        h0minusk.Release();
        X_Y_Z_dXdx.Release();
        dYdx_dYdz_dZdx_dZdz.Release();

        pingpong0.Release();
        pingpong1.Release();

        Displacement.Release();
        Slope.Release();
        Foam.Release();

        h0k = null;
        h0minusk = null;
        X_Y_Z_dXdx = null;
        dYdx_dYdz_dZdx_dZdz = null;

        pingpong0 = null;
        pingpong1 = null;

        Displacement = null;
        Slope = null;
        Foam = null;
    }

    public void Update(float elapsedTime, float deltaT) {
        // Frequency Domain Stuff
        // hkt
        Spectrum_CS.SetFloat("t", elapsedTime);
        Spectrum_CS.Dispatch(0, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);


        // IFFTs
        IFFT(X_Y_Z_dXdx);
        IFFT(dYdx_dYdz_dZdx_dZdz);

        Normalise_CS.Dispatch(0, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);


        // Foam
        Foam_CS.SetFloat("deltaT", deltaT);
        Foam_CS.Dispatch(0, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);


        Slope.GenerateMips();
        Foam.GenerateMips();
    }



    // Helper Functions
    public static RenderTexture CreateRenderTexture(int size, FilterMode fM, TextureWrapMode wM, bool useMipMaps = false, RenderTextureFormat rtf = RenderTextureFormat.ARGBFloat) {
        RenderTexture rt = new RenderTexture(size, size, 0, rtf, RenderTextureReadWrite.Linear);
        rt.enableRandomWrite = true;
        rt.filterMode = fM;
        rt.wrapMode = wM;

        rt.useMipMap = useMipMaps;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 6;
        
        rt.Create();
        return rt;
    }

    public void IFFT(RenderTexture hkt) {
        Graphics.Blit(hkt, pingpong0);
        bool pingpong = false;

        // Horizontal Butterflies
        for (int stage = 0; stage < cascParams.Resolution; stage++) { 
            Butterflies_CS.SetBool("pingpong", pingpong);
            Butterflies_CS.SetInt("stage", stage);
            Butterflies_CS.Dispatch(0, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);
            pingpong = !pingpong;
        }

        // Vertical Butterflies
        for (int stage = 0; stage < cascParams.Resolution; stage++) { 
            Butterflies_CS.SetBool("pingpong", pingpong);
            Butterflies_CS.SetInt("stage", stage);
            Butterflies_CS.Dispatch(1, cascParams.threadGroupsX, cascParams.threadGroupsY, 1);
            pingpong = !pingpong;
        }

        if (pingpong == false) {
            Graphics.Blit(pingpong0, hkt);
        }
        else { 
            Graphics.Blit(pingpong1, hkt);
        }
    }
}
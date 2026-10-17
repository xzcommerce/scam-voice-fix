// Talks only to the official worker shipped with the installed game.
// No network, microphone, audio playback or third-party speech engine.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

public sealed class VoiceWarmupResult {
    public double FirstAudioSeconds, AudioSeconds, GenerationSeconds;
    public string Diagnostics;
}
public static class VoiceWarmup {
    static float[] ReadReference(string path) {
        using (var r = new BinaryReader(File.OpenRead(path))) {
            if (new string(r.ReadChars(4)) != "RIFF") throw new Exception("Unsupported voice reference.");
            r.ReadInt32();
            if (new string(r.ReadChars(4)) != "WAVE") throw new Exception("Unsupported voice reference.");
            int format=0, channels=0, rate=0, bits=0;
            while (r.BaseStream.Position+8 <= r.BaseStream.Length) {
                string id=new string(r.ReadChars(4)); int size=r.ReadInt32();
                long next=r.BaseStream.Position+size+(size%2);
                if (size<0 || next>r.BaseStream.Length) throw new Exception("Damaged voice reference.");
                if (id=="fmt ") { format=r.ReadInt16();channels=r.ReadInt16();rate=r.ReadInt32();r.ReadInt32();r.ReadInt16();bits=r.ReadInt16(); }
                if (id=="data") {
                    if (format!=1 || channels!=1 || rate!=24000 || bits!=16) throw new Exception("Reference must be 24 kHz mono PCM16.");
                    int count=Math.Min(size/2,240000);
                    if(count<24000)throw new Exception("Reference is too short.");
                    float[] samples=new float[count];
                    for(int i=0;i<count;i++)samples[i]=r.ReadInt16()/32768f;
                    return samples;
                }
                r.BaseStream.Position=next;
            }
        }
        throw new Exception("No reference audio.");
    }
    static void Wait(Task task,int milliseconds,string message) {
        if(!task.Wait(milliseconds))throw new TimeoutException(message);
    }
    public static VoiceWarmupResult Run(string runtime,string models,string voice,string log) {
        float[] reference=ReadReference(voice);
        byte[] refBytes=new byte[reference.Length*4];Buffer.BlockCopy(reference,0,refBytes,0,refBytes.Length);
        var info=new ProcessStartInfo(Path.Combine(runtime,"QwenTtsWorker.exe"));
        info.WorkingDirectory=runtime;info.UseShellExecute=false;info.CreateNoWindow=true;
        info.RedirectStandardInput=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
        foreach(string key in new[]{"__GL_SHADER_DISK_CACHE_PATH","__GL_SHADER_DISK_CACHE_APP_NAME","__GL_SHADER_DISK_CACHE_READ_ONLY_APP_NAME","__GL_SHADER_DISK_CACHE_SKIP_CLEANUP"})info.EnvironmentVariables.Remove(key);
        info.EnvironmentVariables["DISABLE_VK_LAYER_VALVE_steam_fossilize_1"]="1";
        info.EnvironmentVariables["DISABLE_VK_LAYER_VALVE_steam_overlay_1"]="1";
        var p=new Process();p.StartInfo=info;
        var errors=new StringBuilder();IntPtr job=IntPtr.Zero;
        p.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)lock(errors)errors.AppendLine(e.Data);};
        var result=new VoiceWarmupResult();
        try {
            p.Start();job=Attach(p);p.PriorityClass=ProcessPriorityClass.BelowNormal;p.BeginErrorReadLine();
            var reader=new BinaryReader(p.StandardOutput.BaseStream);
            var writer=new BinaryWriter(p.StandardInput.BaseStream,Encoding.UTF8);
            var load=Task.Run(delegate {
                writer.Write(1);writer.Write(Path.Combine(models,"qwen-talker-0.6b-base-Q8_0.gguf"));
                writer.Write(Path.Combine(models,"qwen-tokenizer-12hz-Q8_0.gguf"));writer.Write("Vulkan0");writer.Flush();
                int code=reader.ReadInt32();if(code==4)throw new Exception(reader.ReadString());
                if(code!=1 || reader.ReadInt32()!=1)throw new Exception("Unexpected model load response.");
            });
            Wait(load,180000,"Qwen model loading took more than three minutes.");
            var clock=Stopwatch.StartNew();
            var speech=Task.Run(delegate {
                writer.Write(2);writer.Write("Здравствуйте! Да, я вас слышу. Расскажите, пожалуйста, что случилось и чем я могу вам помочь.");
                writer.Write("Russian");writer.Write(reference.Length);writer.Write(refBytes);writer.Flush();
                long total=0;double first=-1;
                while(true) {
                    int code=reader.ReadInt32();if(code==4)throw new Exception(reader.ReadString());if(code==3)break;
                    if(code!=2)throw new Exception("Unexpected speech response.");
                    int count=reader.ReadInt32();if(count<=0 || count>720000)throw new Exception("Invalid speech chunk.");
                    byte[] bytes=reader.ReadBytes(count*4);if(bytes.Length!=count*4)throw new EndOfStreamException();
                    if(first<0)first=clock.Elapsed.TotalSeconds;
                    for(int i=0;i<bytes.Length;i+=4){float value=BitConverter.ToSingle(bytes,i);if(float.IsNaN(value)||float.IsInfinity(value))throw new Exception("Invalid audio samples.");}
                    total+=count;
                }
                if(total==0)throw new Exception("Qwen returned no audio.");
                result.FirstAudioSeconds=first;result.AudioSeconds=total/24000.0;result.GenerationSeconds=clock.Elapsed.TotalSeconds;
            });
            Wait(speech,180000,"Qwen speech preparation took more than three minutes.");
        } finally {
            try{if(!p.HasExited)p.Kill();p.WaitForExit(5000);}catch{}
            lock(errors){result.Diagnostics=errors.ToString();File.WriteAllText(log,result.Diagnostics);}
            p.Dispose();if(job!=IntPtr.Zero)CloseHandle(job);
        }
        return result;
    }
    // Match the game's 4 GiB worker limit, and stop our worker if the installer closes.
    [StructLayout(LayoutKind.Sequential)] struct Basic {public long ProcessTime,JobTime;public uint Flags;public UIntPtr MinWorkingSet,MaxWorkingSet;public uint ActiveProcessLimit;public UIntPtr Affinity;public uint Priority,Scheduling;}
    [StructLayout(LayoutKind.Sequential)] struct Counters {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
    [StructLayout(LayoutKind.Sequential)] struct Extended {public Basic Basic;public Counters IO;public UIntPtr ProcessMemory,JobMemory,PeakProcessMemory,PeakJobMemory;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attrs,string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,ref Extended data,uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    static IntPtr Attach(Process p) {
        IntPtr job=CreateJobObject(IntPtr.Zero,null);Extended limits=new Extended();
        limits.Basic.Flags=9472;limits.ProcessMemory=new UIntPtr(4294967296UL);
        if(job==IntPtr.Zero || !SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(Extended))) || !AssignProcessToJobObject(job,p.Handle)) {
            if(job!=IntPtr.Zero)CloseHandle(job);throw new Exception("Cannot supervise Qwen worker.");
        }
        return job;
    }
}

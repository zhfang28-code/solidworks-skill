using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;

internal static class SolidWorksSmokeTest
{
    private static Feature FindFirstReferencePlane(ModelDoc2 model)
    {
        Feature feature = (Feature)model.FirstFeature();
        while (feature != null)
        {
            if (String.Equals(feature.GetTypeName2(), "RefPlane", StringComparison.OrdinalIgnoreCase))
                return feature;
            feature = (Feature)feature.GetNextFeature();
        }
        throw new InvalidOperationException("找不到零件基准面。");
    }

    private static void Save(ModelDoc2 model, string path)
    {
        int errors = 0;
        int warnings = 0;
        bool ok = model.Extension.SaveAs(
            path,
            (int)swSaveAsVersion_e.swSaveAsCurrentVersion,
            (int)swSaveAsOptions_e.swSaveAsOptions_Silent,
            null,
            ref errors,
            ref warnings);
        if (!ok || errors != 0)
            throw new InvalidOperationException(
                String.Format("保存失败：{0}（errors={1}, warnings={2}）", path, errors, warnings));
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 0 || String.IsNullOrWhiteSpace(args[0]))
        {
            Console.Error.WriteLine("用法：SolidWorksSmokeTest.exe <output-directory> [--close]");
            return 2;
        }

        string outputDirectory = Path.GetFullPath(args[0]);
        Directory.CreateDirectory(outputDirectory);
        string partPath = Path.Combine(outputDirectory, "SolidWorks_API_SmokeTest.SLDPRT");
        string auditPath = Path.Combine(outputDirectory, "SolidWorks_API_SmokeTest.json");
        bool closeWhenFinished = args.Any(
            value => String.Equals(value, "--close", StringComparison.OrdinalIgnoreCase));

        SldWorks application = null;
        bool createdApplication = false;
        ModelDoc2 model = null;

        try
        {
            try
            {
                application = (SldWorks)Marshal.GetActiveObject("SldWorks.Application");
            }
            catch
            {
                application = (SldWorks)new SldWorksClass();
                createdApplication = true;
            }

            application.Visible = true;
            string template = application.GetUserPreferenceStringValue(
                (int)swUserPreferenceStringValue_e.swDefaultTemplatePart);
            if (String.IsNullOrWhiteSpace(template) || !File.Exists(template))
                throw new FileNotFoundException("SolidWorks 默认零件模板不可用。", template);

            model = (ModelDoc2)application.NewDocument(template, 0, 0.0, 0.0);
            if (model == null)
                throw new InvalidOperationException("SolidWorks 新建零件失败。");

            Feature plane = FindFirstReferencePlane(model);
            model.ClearSelection2(true);
            if (!plane.Select2(false, 0))
                throw new InvalidOperationException("选择第一个基准面失败。");

            SketchManager sketch = model.SketchManager;
            sketch.InsertSketch(true);
            sketch.CreateCircleByRadius(0.0, 0.0, 0.0, 0.010);
            sketch.InsertSketch(true);

            Feature boss = model.FeatureManager.FeatureExtrusion3(
                true, false, false,
                (int)swEndConditions_e.swEndCondBlind,
                (int)swEndConditions_e.swEndCondBlind,
                0.010, 0.001,
                false, false, false, false,
                0.0, 0.0,
                false, false, false, false,
                true, true, true,
                (int)swStartConditions_e.swStartSketchPlane,
                0.0, false);
            if (boss == null)
                throw new InvalidOperationException("冒烟测试拉伸失败。");
            boss.Name = "01_API_冒烟测试圆柱_Ø20×10";

            model.EditRebuild3();
            Save(model, partPath);

            string json = String.Format(
                "{{\"status\":\"passed\",\"solidworks_revision\":\"{0}\",\"diameter_mm\":20.0,\"length_mm\":10.0}}",
                application.RevisionNumber().Replace("\\", "\\\\").Replace("\"", "\\\""));
            File.WriteAllText(auditPath, json, new UTF8Encoding(true));
            Console.WriteLine(partPath);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.GetType().FullName + ": " + exception.Message);
            return 1;
        }
        finally
        {
            if (model != null)
            {
                try { application.CloseDoc(model.GetTitle()); } catch { }
            }
            if (closeWhenFinished && createdApplication && application != null)
            {
                try { application.ExitApp(); } catch { }
            }
        }
    }
}

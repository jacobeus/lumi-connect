// LumiShow: runs a LittleFoot program on a LUMI Keys block until this tool exits.
//
// The program is loaded as temporary (ProgramPersistency::setAsTemp), so nothing is
// written to the LUMI's memory. On Ctrl-C or SIGTERM the tool puts the LUMI's own
// program back before exiting.

#include <roli_blocks_basics/roli_blocks_basics.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <csignal>
#include <iostream>

static std::atomic<bool> stopRequested { false };

struct FileProgram : roli::Block::Program
{
    FileProgram (roli::Block& b, juce::String source) : Program (b), code (std::move (source)) {}
    juce::String getLittleFootProgram() override { return code; }
    juce::String code;
};

// Prints what the program reports with sendMessageToHost (kind, a, b). Pitch bend
// moves arrive dozens of times a second, so they are summarised once a second.
struct Reporter : roli::Block::ProgramEventListener, juce::Timer
{
    explicit Reporter (bool verboseOutput) : verbose (verboseOutput) { startTimer (1000); }

    void handleProgramEvent (roli::Block&, const roli::Block::ProgramEventMessage& m) override
    {
        auto kind = m.values[0], a = m.values[1], b = m.values[2];
        if (kind == 1)
            std::cout << "Program running. Octave " << a << ", glide sensitivity " << b << std::endl;
        if (! verbose)
            return;
        if (kind == 2) std::cout << "strike key " << a << " velocity " << b << std::endl;
        if (kind == 3) { ++moves; lastMove = juce::String (a) + ":" + juce::String (b); }
        if (kind == 4) std::cout << "button " << a << ", octave " << b << std::endl;
    }

    void timerCallback() override
    {
        if (moves == 0)
            return;
        std::cout << moves << " pitch bend moves, last key:value " << lastMove << std::endl;
        moves = 0;
    }

    bool verbose;
    int moves = 0;
    juce::String lastMove;
};

struct Show : roli::TopologySource::Listener, juce::Timer
{
    Show (juce::File programFile, bool verbose) : file (programFile), reporter (verbose)
    {
        source.addListener (this);
        startTimer (100);
    }

    void topologyChanged() override
    {
        for (auto& block : source.getCurrentTopology().blocks)
        {
            if (block->getType() != roli::Block::lumiKeysBlock || loaded.contains (block))
                continue;
            auto result = block->setProgram (std::make_unique<FileProgram> (*block, file.loadFileAsString()));
            if (! result.wasOk())
            {
                std::cerr << block->getDeviceDescription() << ": " << result.getErrorMessage() << std::endl;
                continue;
            }
            std::cout << block->getDeviceDescription() << ": " << file.getFileName() << " loaded" << std::endl;
            block->addProgramEventListener (&reporter);
            loaded.add (block);
        }
    }

    // Polls the flag set by the signal handler, which cannot touch the SDK itself.
    void timerCallback() override
    {
        if (! stopRequested)
            return;
        stopTimer();
        for (auto& block : loaded)
            block->resetProgramToDefault();
        std::cout << "LUMI back on its own program." << std::endl;
        juce::Timer::callAfterDelay (500, [] { std::exit (0); });
    }

    juce::File file;
    Reporter reporter;
    roli::PhysicalTopologySource source;
    juce::ReferenceCountedArray<roli::Block> loaded;
};

int main (int argc, char* argv[])
{
    juce::StringArray args;
    for (int i = 1; i < argc; ++i)
        args.add (argv[i]);
    bool verbose = args.contains ("--verbose");
    args.removeString ("--verbose");

    if (args.size() != 1)
    {
        std::cerr << "usage: LumiShow [--verbose] <program.littlefoot>" << std::endl;
        return 2;
    }
    auto file = juce::File::getCurrentWorkingDirectory().getChildFile (args[0]);
    if (! file.existsAsFile())
    {
        std::cerr << "No such file: " << file.getFullPathName() << std::endl;
        return 2;
    }

    std::signal (SIGINT, [] (int) { stopRequested = true; });
    std::signal (SIGTERM, [] (int) { stopRequested = true; });

    juce::ScopedJuceInitialiser_GUI juceInit;
    Show show (file, verbose);
    std::cout << "Waiting for the LUMI. Press Ctrl-C to stop the show." << std::endl;
    while ([[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate distantFuture]]);
}
